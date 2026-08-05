class NotesController < ApplicationController
  before_action :set_own_note, only: %i[ edit update destroy ]

  def index
    @notes = Note.visible_to(Current.user).order(updated_at: :desc).includes(:sections, :user)
  end

  def show
    @note = Note.visible_to(Current.user).find(params[:id])
  end

  def new
    @note = Current.user.notes.new
  end

  def create
    @note = Current.user.notes.new(note_params)
    if @note.save
      redirect_to @note, notice: "Note saved."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @note.update(note_params)
      redirect_to @note, notice: "Note updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @note.destroy!
    redirect_to notes_path, notice: "Note deleted."
  end

  private
    def set_own_note
      @note = Current.user.notes.find(params[:id])
    end

    def note_params
      params.expect(note: [ :title, :body, section_ids: [] ])
    end
end
