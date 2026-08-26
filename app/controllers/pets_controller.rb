class PetsController < ApplicationController
  before_action :set_own_pet, only: %i[ edit update destroy ]

  # The pet's page: the one place her care, food, papers, pictures and cost
  # converge (D-pet-primitive). Her lens's own section page stays what section
  # pages are — the raw browse of everything tagged — and this links to it.
  def show
    @pet = Pet.visible_to(Current.user).includes(:section, :vet).find(params[:id])
    @own = @pet.user_id == Current.user.id
    # A pet who has died or been rehomed keeps her page and her history; what
    # stops is everything that would nag about her (D-pet-primitive).
    @care_statuses = @pet.active? ? Health::CareRadar.new(@pet, viewer: Current.user).statuses : []
    @health_section_id = Section.find_by(slug: "health")&.id
    @events = @pet.items(Event, Current.user).upcoming.includes(:sections, :user).limit(6)
    @tasks = @pet.items(Task, Current.user).open.includes(:sections, :user).limit(6)
    @shelf = Pets::FoodShelf.new(@pet)
    @papers = Pets::Papers.for(@pet, Current.user)
    @photos = @pet.items(Photo, Current.user).with_attached_image.order(taken_at: :desc, id: :desc).limit(12)
    # The money side is the owner's own: envelopes and the ledger are per-user
    # and private (BudgetCategory has no grants path), so a shared viewer sees
    # the shelf and not the bill.
    @cost = Pets::CostOfCare.new(Current.user) if @own
  end

  def new
    @pet = Current.user.pets.new(species: params[:species].presence || "dog")
  end

  def create
    @pet = Current.user.pets.new(pet_params)
    # The lens is the pet's, so it is created with her and never separately —
    # a pet without one could not be tagged, which is the whole mechanism.
    @pet.section = Pets::Lens.create!(@pet.name) if @pet.name.present?

    if @pet.save
      share_with_household if params[:share_with_household].present?
      redirect_to @pet, notice: "#{@pet.name} added. Anything about her can be filed under her name now."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @pet.update(pet_params)
      Pets::Lens.rename!(@pet.section, @pet.name)
      redirect_to @pet, notice: "#{@pet.name} updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # Removing the pet removes her lens, which is the only way that lens goes
  # (GroupsController refuses it). Tagged items survive and keep their other
  # tags — the section_taggings go with the section, as they do for any lens.
  def destroy
    section = @pet.section
    @pet.destroy!
    section.destroy!
    redirect_to section_path("people"), notice: "#{@pet.name} removed. Everything filed under her name kept its other tags."
  end

  private
    def set_own_pet
      @pet = Current.user.pets.find(params[:id])
    end

    # Sharing a pet is two ordinary grants, both visible and revocable in
    # Settings (D9): the record itself, so her page opens, and her lens, so
    # everything filed under her name comes with it. Nothing is implied by
    # the household relationship — this runs only when the box is ticked.
    def share_with_household
      Current.user.household.users.where.not(id: Current.user.id).find_each do |member|
        Current.user.granted_access_grants.find_or_create_by(grantee: member, subject: @pet)
        Current.user.granted_access_grants.find_or_create_by(grantee: member, subject: @pet.section)
      end
    end

    def pet_params
      params.expect(pet: [ :name, :species, :breed, :sex, :color, :microchip, :born_on, :born_on_estimated,
        :adopted_on, :weight_kg, :died_on, :left_on, :notes, :vet_id, :avatar ])
    end
end
