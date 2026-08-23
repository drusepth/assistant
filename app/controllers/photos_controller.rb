class PhotosController < ApplicationController
  PER_PAGE = 120
  # How many places the map page lists under the map. The map itself always
  # carries every pin.
  PLACES_LISTED = 24

  before_action :set_own_photo, only: %i[ edit update destroy ingest caption apply_suggestion ]

  def index
    # Following a map pin (D-travel-facet). Locations are owner-only (Q14),
    # so a place filter starts from your own photos — a shared photo's
    # whereabouts are not the grantee's to search by.
    @place = parse_place(params[:near])
    @place_name = Datasets::Places.current.nearest(*@place) if @place
    base = @place ? Current.user.photos.near(*@place) : Photo.visible_to(Current.user)

    if params[:section].present?
      @section = Section.find_by!(slug: params[:section])
      base = base.in_section([ @section.id, *@section.children.ids ])
    end
    if params[:person].present?
      @person = Person.visible_to(Current.user).find(params[:person])
      base = base.joins(:photo_people).where(photo_people: { person_id: @person.id })
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

  # The world map of everywhere you've taken a photo (D-travel-facet). Own
  # photos only, always: coordinates are owner-only (Q14) and a map is the
  # surface that would leak them furthest.
  def map
    base = Current.user.photos.located
    @years = base.distinct.pluck(Arel.sql("strftime('%Y', taken_at)")).sort.reverse

    if params[:year].present?
      @year = params[:year].to_i
      base = base.where(taken_at: Time.zone.local(@year)...Time.zone.local(@year + 1))
    end

    @map = Photos::Map.new(base)
    @places = @map.recent_pins(PLACES_LISTED)
    @unplaced = Current.user.photos.where(latitude: nil).count
  end

  def show
    @photo = Photo.visible_to(Current.user).find(params[:id])
    # Tags name, they never grant: a viewer sees only tagged people they
    # could already see.
    @person_tags = @photo.photo_people.joins(:person)
      .merge(Person.visible_to(Current.user)).includes(:person)
    if @photo.user_id == Current.user.id
      @taggable_people = Person.visible_to(Current.user)
        .where.not(id: @photo.photo_people.select(:person_id)).order(:name)
    end
  end

  # Batch capture: files from the multipart fallback or signed blob ids from
  # direct upload — attach accepts both, so one path serves JS and no-JS.
  # An album_id (from an album page's upload zone) files the batch there too.
  def create
    album = Current.user.albums.find(params.dig(:photos, :album_id)) if params.dig(:photos, :album_id).present?
    images = Array(params.dig(:photos, :images)).reject(&:blank?)
    return redirect_back_to_library(album, alert: "Choose some photos first.") if images.empty?

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
          album&.album_photos&.create!(photo: photo)
          added += 1
        end
      else
        rejected += 1
      end
    end

    redirect_back_to_library(album, notice: upload_summary(added, skipped, rejected))
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

  def caption
    if @photo.captionable_profile
      @photo.enqueue_caption!
      redirect_to @photo, notice: "Describing — check back in a moment."
    else
      redirect_to @photo, alert: "Photo descriptions need a model marked as accepting images in Settings."
    end
  end

  def apply_suggestion
    section = Section.find_by!(slug: params.expect(:slug))
    @photo.sections << section unless @photo.sections.include?(section)
    @photo.update!(suggested_sections: @photo.suggested_sections - [ section.slug ])
    redirect_to @photo, notice: "Tagged with #{section.qualified_name}."
  end

  private
    def set_own_photo
      @photo = Current.user.photos.find(params[:id])
    end

    def photo_params
      params.expect(photo: [ :title, :caption, :taken_at, section_ids: [] ])
    end

    # "48.8566,2.3522" from a map pin. Anything else — a hand-edited URL,
    # a value out of range — is no filter rather than an error page.
    def parse_place(value)
      return nil if value.blank?

      latitude, longitude = value.to_s.split(",", 2).map { |part| Float(part.strip, exception: false) }
      return nil unless latitude && longitude
      return nil unless latitude.abs <= 90 && longitude.abs <= 180

      [ latitude, longitude ]
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

    def redirect_back_to_library(album = nil, **flash)
      redirect_back fallback_location: album || photos_path, **flash
    end

    def upload_summary(added, skipped, rejected)
      parts = []
      parts << "#{added} #{"photo".pluralize(added)} added" if added.positive?
      parts << "#{skipped} #{skipped == 1 ? "duplicate" : "duplicates"} skipped" if skipped.positive?
      parts << "#{rejected} #{rejected == 1 ? "file wasn't" : "files weren't"} an image" if rejected.positive?
      parts.empty? ? "Nothing added." : parts.join(", ") + "."
    end
end
