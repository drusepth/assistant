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

    if save_with_vet
      share_with_household if params[:share_with_household].present?
      redirect_to @pet, notice: "#{@pet.name} added. Anything about #{@pet.pronouns.object} can be filed under #{@pet.pronouns.possessive} name now."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    @pet.assign_attributes(pet_params)
    if save_with_vet
      Pets::Lens.rename!(@pet.section, @pet.name)
      redirect_to @pet, notice: "#{@pet.name} updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # Removing the pet removes her lens, which is the only way that lens goes
  # (GroupsController refuses it). The cascade lives on the model, so every
  # path removes both — this one only says so.
  def destroy
    @pet.destroy!
    redirect_to section_path("pets"), notice: "#{@pet.name} removed. Everything filed under #{@pet.pronouns.possessive} name kept its other tags."
  end

  private
    # The vet arrives as a typed name and phone, and a new name becomes a
    # contact (Pets::VetContact). One transaction with the pet, so a form
    # that fails validation doesn't leave a stray contact behind; the
    # contact is sorted into sections only once it has really been saved.
    def save_with_vet
      # Only a form that carries the vet box can change the vet.
      typed = pet_params.key?(:vet_name)

      saved = Pet.transaction do
        @pet.vet = Pets::VetContact.resolve(Current.user, name: @pet.vet_name, phone: @pet.vet_phone) if typed
        @pet.save || raise(ActiveRecord::Rollback)
      end
      @pet.vet.enqueue_auto_sort! if saved && @pet.vet&.previously_new_record?
      saved
    end

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

    # The form posts `weight` in the owner's own unit (Units); the column is
    # pounds, which `weight_lb` still sets directly.
    def pet_params
      params.expect(pet: [ :name, :species, :breed, :sex, :pronoun, :neutered, :color, :microchip, :born_on, :born_on_estimated,
        :adopted_on, :weight, :weight_lb, :died_on, :left_on, :notes, :avatar, :vet_name, :vet_phone ]).tap do |attributes|
        attributes[:weight_lb] = Current.user.units.lb_from(attributes.delete(:weight)) if attributes.key?(:weight)
      end
    end
end
