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

  private
    def set_own_document
      @document = Current.user.documents.find(params[:id])
    end

    def document_params
      params.expect(document: [ :title, :description, :file, section_ids: [] ])
    end
end
