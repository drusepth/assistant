# A pet's vaccine record (D-pet-vaccinations): the full history, the
# visit-shaped log form, per-dose edits, and the one-sheet record for the
# kennel.
#
# Who may do what: anyone the pet is visible to can read the record and log a
# dose — the spouse who took the dog to the vet is the one holding the
# certificate — and a dose is edited or removed by whoever logged it or by the
# pet's owner. Unlike a diet, a dose is a fact about the visit rather than a
# decision about the pet, so the person who was there gets to write it down.
class PetVaccinationsController < ApplicationController
  before_action :set_pet
  before_action :set_dose, only: %i[ edit update destroy ]

  def index
    @status = Pets::VaccineStatus.new(@pet, viewer: Current.user)
  end

  def new
    visit = @pet.items(Event, Current.user).find_by(id: params[:event_id]) if params[:event_id].present?
    @log = Pets::VaccineLog.new(pet: @pet, user: Current.user,
      given_on: (visit ? visit.starts_at.to_date : Date.current).iso8601,
      event_id: visit&.id, vet_id: @pet.vet_id, rows: preticked_rows)
  end

  def create
    @log = Pets::VaccineLog.new(log_params.merge(pet: @pet, user: Current.user))
    if @log.save
      names = @log.doses.map(&:vaccine_label).to_sentence
      redirect_to pet_vaccinations_path(@pet), notice: "Logged #{names} for #{@pet.name}."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    attrs = dose_params
    # A newly typed date is the certificate's; it replaces a picked duration
    # rather than being recomputed from it on the next save. The form always
    # sends the stored date back, so only a *changed* one counts as typed.
    attrs[:duration_months] = nil if attrs[:due_on].present? && attrs[:due_on] != @dose.due_on&.iso8601
    if @dose.update(attrs)
      redirect_to pet_vaccinations_path(@pet), notice: "#{@dose.vaccine_label} updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @dose.destroy!
    redirect_to pet_vaccinations_path(@pet), notice: "#{@dose.vaccine_label} dose from #{@dose.given_on.strftime("%B %-d, %Y")} removed."
  end

  # The printable one-sheet: exactly what the share link shows, and nothing
  # a kennel has no business reading (reactions, notes, cost).
  def record
    @status = Pets::VaccineStatus.new(@pet, viewer: Current.user)
    @links = @pet.user_id == Current.user.id ? Current.user.share_links.where(subject: @pet).order(created_at: :desc) : ShareLink.none
  end

  private
    def set_pet
      @pet = Pet.visible_to(Current.user).includes(:section, :vet).find(params[:pet_id])
    end

    def set_dose
      @dose = @pet.pet_vaccinations.find(params[:id])
      return if @dose.user_id == Current.user.id || @pet.user_id == Current.user.id

      redirect_to pet_vaccinations_path(@pet), alert: "Only #{@dose.user&.name || "whoever logged it"} or #{@pet.name}'s owner can change that dose."
    end

    # A link can say which vaccine it came from ("Log a dose" on one row of
    # the card), so the form opens with that one ticked.
    def preticked_rows
      Array(params[:vaccine]).compact_blank.to_h { |key| [ key.to_s, { "include" => "1" } ] }
    end

    # The visit's fields, plus one row per vaccine keyed by what the form
    # rendered — a catalog key for her species or "other_N" — each permitted
    # field by field. A key the form couldn't have rendered is dropped.
    def log_params
      attrs = params.expect(log: Pets::VaccineLog::VISIT_FIELDS)
      submitted = params.dig(:log, :rows)
      allowed = Pets::Vaccines.for(@pet.species).map(&:key) + Pets::VaccineLog.new(pet: @pet).other_keys
      rows = submitted.respond_to?(:keys) ? (submitted.keys.map(&:to_s) & allowed).to_h { |key| [ key, submitted.require(key).permit(*Pets::VaccineLog::ROW_FIELDS).to_h ] } : {}
      attrs.merge(rows: rows)
    end

    def dose_params
      params.expect(pet_vaccination: [ :kind, :vaccine_key, :name, :given_on, :due_on, :duration_months,
        :administered_by, :product, :lot_number, :tag_number, :site, :series_dose, :reaction, :notes ])
    end
end
