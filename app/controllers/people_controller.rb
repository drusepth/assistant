class PeopleController < ApplicationController
  before_action :set_own_person, only: %i[ edit update destroy ]

  def index
    @people = Person.visible_to(Current.user).order(:name).includes(:sections, :user)
  end

  def show
    @person = Person.visible_to(Current.user).find(params[:id])
  end

  def new
    @person = Current.user.people.new
  end

  def create
    @person = Current.user.people.new(person_params)
    if @person.save
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

  private
    def set_own_person
      @person = Current.user.people.find(params[:id])
    end

    def person_params
      params.expect(person: [ :name, :relationship, :email, :phone, :birthday, :notes, :linked_user_id, section_ids: [] ])
    end
end
