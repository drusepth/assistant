# The trip's shared thread (D-trip-companions). Any traveller writes;
# a comment is removed by its author or by the trip's owner.
class TripCommentsController < ApplicationController
  include TripAccess

  def create
    trip = find_trip_as_traveler(params[:trip_id])
    comment = trip.comments.new(body: params.dig(:trip_comment, :body), user: Current.user)
    if comment.save
      redirect_to trip_path(trip, anchor: "comments")
    else
      redirect_to trip_path(trip, anchor: "comments"), alert: comment.errors.full_messages.to_sentence
    end
  end

  def destroy
    comment = TripComment.find(params[:id])
    trip = find_trip_as_traveler(comment.trip_id)
    raise ActiveRecord::RecordNotFound unless comment.editable_by?(Current.user)

    comment.destroy!
    redirect_to trip_path(trip, anchor: "comments"), notice: "Comment removed."
  end
end
