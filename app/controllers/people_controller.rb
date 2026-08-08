class PeopleController < ApplicationController
  before_action :set_own_person, only: %i[ edit update destroy log_contact ]

  def index
    @people = Person.visible_to(Current.user).order(:name).includes(:sections, :user)
  end

  def show
    @person = Person.visible_to(Current.user).find(params[:id])
    @photos = Photo.visible_to(Current.user)
      .joins(:photo_people).where(photo_people: { person_id: @person.id })
      .with_attached_image.order(taken_at: :desc, id: :desc).limit(12)
  end

  def new
    @person = Current.user.people.new
  end

  def create
    @person = Current.user.people.new(person_params)
    if @person.save
      @person.enqueue_auto_sort!
      redirect_to @person, notice: "#{@person.name} added."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @person.update(person_params)
      redirect_to @person, notice: "#{@person.name} updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @person.destroy!
    redirect_to people_path, notice: "Person removed."
  end

  # The Q8 contact-recency signal, one tap. Deliberately manual — the app
  # can't see your texts and shouldn't pretend to.
  def log_contact
    @person.update!(last_contacted_on: Date.current)
    redirect_back fallback_location: person_path(@person), notice: "Noted — you talked to #{@person.name} today."
  end

  private
    def set_own_person
      @person = Current.user.people.find(params[:id])
    end

    def person_params
      params.expect(person: [ :name, :relationship, :email, :phone, :address, :birthday, :notes, :linked_user_id, section_ids: [] ])
    end
end
