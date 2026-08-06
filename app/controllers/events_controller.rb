class EventsController < ApplicationController
  before_action :set_own_event, only: %i[ edit update destroy ]

  def index
    @events = Event.visible_to(Current.user).upcoming.includes(:sections, :user)
  end

  def show
    @event = Event.visible_to(Current.user).find(params[:id])
  end

  def new
    @event = Current.user.events.new(starts_at: params[:date]&.to_date&.noon)
  end

  def create
    @event = Current.user.events.new(event_params)
    if @event.save
      redirect_to calendar_path, notice: "Event added."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @event.update(event_params)
      redirect_to @event, notice: "Event updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @event.destroy!
    redirect_to calendar_path, notice: "Event deleted."
  end

  private
    def set_own_event
      @event = Current.user.events.find(params[:id])
    end

    def event_params
      params.expect(event: [ :title, :description, :starts_at, :ends_at, :all_day, :location, :goal_id, section_ids: [] ])
    end
end
