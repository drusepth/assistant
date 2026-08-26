# Posting photos to a trip (D-trip-companions): the explicit act that
# shares them with everyone travelling on it. The picker offers only the
# poster's *own* photos taken during the trip's dates — by date, never by
# coordinates, so a companion without the owner's box still gets a full
# picker and nothing location-derived crosses users.
class TripPhotoPostsController < ApplicationController
  include TripAccess

  PICKER_LIMIT = 200

  def new
    @trip = find_trip_as_traveler(params[:trip_id])
    already = @trip.trip_photos.where(user: Current.user).pluck(:photo_id)
    @photos = Current.user.photos.with_attached_image
      .where(taken_at: @trip.starts_on.beginning_of_day..@trip.ends_on.end_of_day)
      .where.not(id: already)
      .order(taken_at: :asc, id: :asc).limit(PICKER_LIMIT)
  end

  def create
    trip = find_trip_as_traveler(params[:trip_id])
    photos = Current.user.photos.where(id: Array(params[:photo_ids]))
    posted = photos.count { |photo| trip.trip_photos.create(photo: photo, user: Current.user).persisted? }

    if posted.positive?
      redirect_to trip_path(trip, anchor: "photos"), notice: "#{helpers.pluralize(posted, "photo")} posted to the trip."
    else
      redirect_to new_trip_photo_post_path(trip), alert: "Pick at least one photo."
    end
  end

  def destroy
    post = TripPhoto.find(params[:id])
    trip = find_trip_as_traveler(post.trip_id)
    raise ActiveRecord::RecordNotFound unless post.user_id == Current.user.id || trip.user_id == Current.user.id

    post.destroy!
    redirect_to trip_path(trip, anchor: "photos"), notice: "Photo taken off the trip — it stays in the library."
  end
end
