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
    @document = Current.user.documents.new
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
    @drafts = @document.landing_drafts(landing_context).select { |draft| draft.status == "proposed" }
  end

  # The Save click. Every kept card goes back through its kind; a card that
  # fails re-renders the page with its error in place and nothing lands.
  def land
    @document = Current.user.documents.find(params[:id])
    result = Documents::Land.new(document: @document, user: Current.user,
      submissions: params.fetch(:landings, {}).permit!).call

    if result.ok?
      count = result.saved.size
      notice = count.zero? ? "Nothing saved — the file stays in the vault." :
        "Saved #{count} #{"thing".pluralize(count)} from “#{@document.title}”."
      redirect_to @document, notice: notice
    else
      @drafts = result.drafts
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

    def document_params
      params.expect(document: [ :title, :description, :file, :health_plan, section_ids: [] ])
    end
end
