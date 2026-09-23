class DocumentsController < ApplicationController
  before_action :set_own_document, only: %i[ edit update destroy ]

  def index
    @documents = Document.visible_to(Current.user).order(created_at: :desc)
      .includes(:sections, :user, file_attachment: :blob)
    if params[:section].present?
      @section = Section.find_by!(slug: params[:section])
      @documents = @documents.in_section([ @section.id, *@section.children.ids ])
    end
  end

  def show
    @document = Document.visible_to(Current.user).find(params[:id])
  end

  def new
    # Pre-tags arrive from links like a pet's "Add a document", so the upload
    # is filed under her name rather than left for auto-sort to guess.
    @document = Current.user.documents.new(params.permit(section_ids: []))
  end

  def create
    @document = Current.user.documents.new(document_params)
    if @document.save
      @document.enqueue_analysis! if @document.analyzable_profile
      redirect_to @document, notice: "Document added to the vault."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @document.update(document_params)
      redirect_to @document, notice: "Document updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @document.destroy!
    redirect_to documents_path, notice: "Document deleted."
  end

  def analyze
    @document = Current.user.documents.find(params[:id])
    if @document.analyzable_profile
      @document.enqueue_analysis!
      redirect_to @document, notice: "Analyzing — check back in a moment."
    else
      redirect_to @document, alert: "Configure an AI model in Settings first."
    end
  end

  # The review page (D-document-intake): what the document proposes, as
  # prefilled, editable cards. Owner-only — the landings would be the
  # owner's rows.
  def review
    @document = Current.user.documents.find(params[:id])
    drafts = @document.landing_drafts(landing_context)
    @drafts = drafts.select { |draft| draft.status == "proposed" }
    @skipped = drafts.select { |draft| draft.status == "skipped" }
  end

  # The way back to a skipped landing: it becomes proposed again and
  # returns to the checklist, unticked-by-default no longer.
  def unskip
    @document = Current.user.documents.find(params[:id])
    landings = @document.landings.deep_dup
    entry = landings.find { |candidate| candidate["fingerprint"] == params[:fingerprint] && candidate["status"] == "skipped" }
    entry["status"] = "proposed" if entry
    @document.update!(landings: landings)
    redirect_to review_document_path(@document)
  end

  # The Save click. Every kept card goes back through its kind; a card that
  # fails re-renders the page with its error in place and nothing lands.
  def land
    @document = Current.user.documents.find(params[:id])
    result = Documents::Land.new(document: @document, user: Current.user, submissions: landing_params).call

    if result.ok?
      count = result.saved.size
      notice = count.zero? ? "Nothing saved — the file stays in the vault." :
        "Saved #{count} #{"thing".pluralize(count)} from “#{@document.title}”."
      redirect_to @document, notice: notice
    else
      @drafts = result.drafts
      @skipped = @document.landing_drafts(landing_context).select { |draft| draft.status == "skipped" }
      render :review, status: :unprocessable_entity
    end
  end

  def apply_suggestion
    @document = Current.user.documents.find(params[:id])
    section = Section.find_by!(slug: params.expect(:slug))

    @document.sections << section unless @document.sections.include?(section)
    @document.update!(suggested_sections: @document.suggested_sections - [ section.slug ])
    redirect_to @document, notice: "Tagged with #{section.qualified_name}."
  end

  private
    def set_own_document
      @document = Current.user.documents.find(params[:id])
    end

    def landing_context
      Landing::Context.new(user: Current.user, document: @document)
    end

    # The review form's params, permitted per card against the fields the
    # registry declares for *that card's kind* (D-landing-registry). The
    # closed set that validates the model's answer permits the form's
    # answer too, so a blanket `permit!` never has to appear here: a key no
    # kind declares is dropped at the boundary rather than trusted to be
    # ignored downstream, and an index the document doesn't have is not a
    # card at all.
    def landing_params
      permitted = @document.landings.each_with_index.filter_map do |entry, index|
        kind = Landing.find(entry["kind"]) or next

        [ index.to_s, [ :keep, { attributes: kind.fields.map { |field| field.name.to_sym } } ] ]
      end.to_h

      params.fetch(:landings, ActionController::Parameters.new).permit(permitted)
    end

    def document_params
      params.expect(document: [ :title, :description, :file, :health_plan, section_ids: [] ])
    end
end
