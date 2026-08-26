# The food shelf (D-pet-food-shelf). Adding, superseding and pricing what a
# pet eats — always on your own pet, because a diet is a decision the owner
# made, not something a shared viewer edits.
class PetFoodsController < ApplicationController
  before_action :set_pet
  before_action :set_food, only: %i[ update end_food reorder ]

  def create
    food = @pet.pet_foods.new(food_params)
    food.started_on ||= Date.current

    if food.save
      # Superseding, not replacing: the old row keeps its dates so the diet
      # history stays readable.
      @pet.pet_foods.current.where.not(id: food.id).where(form: food.form)
        .update_all(ended_on: Date.current) if params[:replaces_current].present?

      redirect_to @pet, notice: "#{food.display_name} added to #{@pet.name}'s shelf."
    else
      redirect_to @pet, alert: food.errors.full_messages.to_sentence
    end
  end

  def update
    if @food.update(food_params)
      redirect_to @pet, notice: "#{@food.display_name} updated."
    else
      redirect_to @pet, alert: @food.errors.full_messages.to_sentence
    end
  end

  # Ending a food is what keeps the history — there is no destroy here on
  # purpose. (A row typed by mistake can still be edited to nothing useful,
  # but the shelf would rather keep a wrong date than lose a real one.)
  def end_food
    @food.update!(ended_on: params[:ended_on].presence || Date.current)
    redirect_to @pet, notice: "#{@food.display_name} moved to #{@pet.name}'s diet history."
  end

  # The reorder date is arithmetic; this is the one click that turns it into
  # something the calendar and the renewal radar can see (D-pet-food-shelf).
  def reorder
    date = @food.runs_out_on
    return redirect_to(@pet, alert: "That food doesn't carry enough numbers to work out a reorder date.") if date.nil?

    title = Pets::FoodShelf.reorder_title(@food)
    event = Current.user.events.where(title: title).where(starts_at: Date.current.beginning_of_day..).first
    if event
      return redirect_to @pet, notice: "Already on the calendar for #{event.starts_at.to_date.strftime("%B %-d")}."
    end

    event = Current.user.events.create!(title: title, starts_at: date.beginning_of_day, all_day: true,
      # A reorder is not a visit, and the radar must not count it as one —
      # the medication-refill rule (HEALTH.md §7), same reason.
      care_kind: Health::CareRadar::EXCLUDED)
    event.sections << [ @pet.section, money_section ].compact

    redirect_to @pet, notice: "Reorder on the calendar for #{date.strftime("%B %-d")}."
  end

  private
    def set_pet
      @pet = Current.user.pets.find(params[:pet_id])
    end

    def set_food
      @food = @pet.pet_foods.find(params[:id])
    end

    def money_section = Section.find_by(slug: "money")

    def food_params
      params.expect(pet_food: [ :name, :brand, :form, :amount_per_day, :unit, :package_amount,
        :package_cost, :started_on, :opened_on, :notes ]).tap do |attrs|
        # Money is typed in currency and stored in cents — no floats in money
        # math anywhere (MoneyHelper's rule).
        cost = attrs.delete(:package_cost)
        attrs[:package_cost_cents] = cost.present? ? (cost.to_f * 100).round : nil
      end
    end
end
