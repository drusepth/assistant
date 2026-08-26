class PeopleController < ApplicationController
  before_action :set_own_person, only: %i[ edit update destroy log_contact ]

  # The roster, and — since D-people-circles — the circle's own full view:
  # the circle card on the People page links here filtered rather than to a
  # fourth People surface. Circle mode is own-people-only, because the flag
  # is the owner's intent (D-people-dashboard).
  #
  # Alphabetical in every mode, circle included (D-address-book-directory):
  # a directory is the one list whose order the reader already knows before
  # it loads, and staleness has its own surface — the People page's Reach
  # out rows — where recency order is the point rather than a surprise.
  def index
    @directory = People::Directory.new(Current.user,
      query: params[:q], circle: params[:circle].present?, group_slug: params[:group])
    # Still assigned for the view's filter row and for anything that renders
    # the roster's shape; the directory owns the querying.
    @circle_only = @directory.circle?
    @circle_size = @directory.circle_size
    @people = @directory.people
  end

  def show
    @person = Person.visible_to(Current.user).find(params[:id])
    # Groups this person is in, and the ones they could join
    # (D-people-circles) — the second front door for membership, because
    # "oh, she's in the book club" is a thought you have here.
    all_groups = Section.find_by(slug: "people")&.children.to_a
    @groups, @group_candidates = all_groups.partition { |group| @person.section_ids.include?(group.id) }
    @photos = Photo.visible_to(Current.user)
      .joins(:photo_people).where(photo_people: { person_id: @person.id })
      .with_attached_image.order(taken_at: :desc, id: :desc).limit(12)
  end

  # `name:` carries a search that came up empty straight into the form
  # (D-address-book-directory): you looked for Rosa, we don't have Rosa, the
  # next thing you want is Rosa with her name already typed.
  def new
    @person = Current.user.people.new(name: params[:name])
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
      # Handing a contact back: unticking every section on the edit form
      # leaves them unfiled, which is the assistant's cue to file them again
      # (D-people-auto-filing). enqueue_auto_sort! no-ops when they're tagged.
      @person.enqueue_auto_sort!
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
      params.expect(person: [ :name, :relationship, :email, :phone, :address, :birthday, :notes, :linked_user_id, :avatar, section_ids: [] ])
    end
end
