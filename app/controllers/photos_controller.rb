class PhotosController < ApplicationController
  PER_PAGE = 120

  before_action :set_own_photo, only: %i[ edit update destroy ingest ]

  def index
    base = Photo.visible_to(Current.user)
    if params[:section].present?
      @section = Section.find_by!(slug: params[:section])
      base = base.in_section([ @section.id, *@section.children.ids ])
    end
    @years = base.distinct.pluck(Arel.sql("strftime('%Y', taken_at)")).sort.reverse

    if params[:year].present?
      @year = params[:year].to_i
      base = base.where(taken_at: Time.zone.local(@year)...Time.zone.local(@year + 1))
    end

    scope = base.with_attached_image.includes(:sections, :user)
      .order(taken_at: :desc, id: :desc)
    scope = cursored(scope) if params[:before_at].present?

    page = scope.limit(PER_PAGE + 1).to_a
    @more = page.size > PER_PAGE
    @photos = page.first(PER_PAGE)
  end

  def show
    @photo = Photo.visible_to(Current.user).find(params[:id])
  end

  # Batch capture: files from the multipart fallback or signed blob ids from
  # direct upload — attach accepts both, so one path serves JS and no-JS.
  def create
    images = Array(params.dig(:photos, :images)).reject(&:blank?)
    return redirect_back_to_library(alert: "Choose some photos first.") if images.empty?

    added = skipped = rejected = 0
    images.each do |image|
      photo = Current.user.photos.new(image: image)
      if photo.save
        # Same bytes already in the library (or earlier in this batch):
        # quietly drop the copy rather than store it twice.
        if photo.duplicate_of_existing?
          photo.destroy!
          skipped += 1
        else
          photo.enqueue_ingest!
          added += 1
        end
      else
        rejected += 1
      end
    end

    redirect_back_to_library(notice: upload_summary(added, skipped, rejected))
  end

  def edit
  end

  def update
    if @photo.update(photo_params)
      redirect_to @photo, notice: "Photo updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @photo.destroy!
    redirect_to photos_path, notice: "Photo deleted."
  end

  def ingest
    @photo.enqueue_ingest!
    redirect_to @photo, notice: "Processing — check back in a moment."
  end

  private
    def set_own_photo
      @photo = Current.user.photos.find(params[:id])
    end

    def photo_params
      params.expect(photo: [ :title, :caption, :taken_at, section_ids: [] ])
    end

    # Keyset pagination: strictly older than the last photo on the previous
    # page, with the id breaking exact-timestamp ties.
    def cursored(scope)
      at = Time.zone.iso8601(params[:before_at])
      scope.where("taken_at < :at OR (taken_at = :at AND photos.id < :id)",
        at: at, id: params[:before_id].to_i)
    rescue ArgumentError
      scope
    end

    def redirect_back_to_library(**flash)
      redirect_back fallback_location: photos_path, **flash
    end

    def upload_summary(added, skipped, rejected)
      parts = []
      parts << "#{added} #{"photo".pluralize(added)} added" if added.positive?
      parts << "#{skipped} #{skipped == 1 ? "duplicate" : "duplicates"} skipped" if skipped.positive?
      parts << "#{rejected} #{rejected == 1 ? "file wasn't" : "files weren't"} an image" if rejected.positive?
      parts.empty? ? "Nothing added." : parts.join(", ") + "."
    end
end
