class AlbumsController < ApplicationController
  before_action :set_own_album, only: %i[ edit update destroy add_photos remove_photos ]

  def index
    @albums = Album.visible_to(Current.user).includes(:user, :photos, cover_photo: { image_attachment: :blob })
      .order(updated_at: :desc)
  end

  def show
    @album = Album.visible_to(Current.user).find(params[:id])
    @photos = @album.photos.visible_to(Current.user)
      .with_attached_image.includes(:sections).order(taken_at: :desc, id: :desc)
  end

  def new
    @album = Current.user.albums.new
  end

  def create
    @album = Current.user.albums.new(album_params)
    if @album.save
      redirect_to @album, notice: "Album created — now add some photos."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @album.update(album_params)
      redirect_to @album, notice: "Album updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # Deleting removes the container only — never the photos in it.
  def destroy
    @album.destroy!
    redirect_to albums_path, notice: "Album deleted. Its photos are still in your library."
  end

  def add_photos
    photos = Current.user.photos.where(id: photo_id_params).where.not(id: @album.photo_ids)
    photos.each { |photo| @album.album_photos.create!(photo: photo) }
    @album.touch if photos.any?

    redirect_back fallback_location: @album,
      notice: "#{photos.size} #{"photo".pluralize(photos.size)} added to #{@album.title}."
  end

  def remove_photos
    removed = @album.album_photos.where(photo_id: photo_id_params).destroy_all

    redirect_back fallback_location: @album,
      notice: "#{removed.size} #{"photo".pluralize(removed.size)} removed from #{@album.title}."
  end

  private
    def set_own_album
      @album = Current.user.albums.find(params[:id])
    end

    def album_params
      params.expect(album: [ :title, :description, :cover_photo_id ])
    end

    def photo_id_params
      Array(params[:photo_ids]).reject(&:blank?)
    end
end
