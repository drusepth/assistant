module Admin
  # The reset switch (D-household-reset): empty a household of everything it
  # owns and hand the instance back to the first-run signup form.
  #
  # A self-hosted app is its own staging environment. There is no seed script
  # to re-run, no `db:reset` on a box you reach through a browser, and the
  # fastest way to try the onboarding flow a second time is to be a brand new
  # instance again — so filling the app with throwaway data while trying it
  # out is a one-way trip without this.
  #
  # Deliberately not a "delete my account" feature: it takes the whole
  # household, members included, because landing back on the signup form is
  # the entire point. The takeable copy of your life is /settings → Export;
  # this is the other end of ownership, the part where you get to throw it
  # all away.
  module HouseholdReset
    # Typed, not clicked. A dialog is muscle memory after the third reset;
    # a word you have to spell is the last thing standing between a testing
    # afternoon and a real household's records.
    CONFIRMATION = "RESET"

    # What "everything" means in the flash: the primitives plus their
    # containers. Runs, suggestions, grants, feeds and settings go with the
    # accounts too — they just aren't what anyone counts.
    COUNTED_ASSOCIATIONS = %i[ events tasks documents people goals notes photos albums ].freeze

    module_function

    def confirmed?(input) = input.to_s.strip == CONFIRMATION

    # Counts of what a reset would take, for the confirmation card. Cheap
    # enough (a handful of COUNTs) to render on every /admin visit, and the
    # button has no business being vague about what it does.
    def preview(household) = summarize(household.users.to_a)

    # Returns the same summary, describing what actually went.
    def call(household)
      users = household.users.to_a
      summary = summarize(users)

      purge_attachments(household, users)
      # The error log keeps a foreign key to users but is not cascaded from
      # them — a failure outlives the account that hit it on purpose — so
      # these rows go first or the destroy below trips the constraint.
      AppError.where(user: users).delete_all

      household.destroy!
      clear_instance_leftovers

      summary
    end

    def summarize(users)
      {
        members: users.size,
        items: COUNTED_ASSOCIATIONS.sum { |name| users.sum { |user| user.public_send(name).count } }
      }
    end

    # Attachments are cascaded as purge_later, which leaves the bytes on disk
    # until a job runs — fine for one deleted document, wrong for a reset,
    # where the next screen claims a clean instance. Purge them here so the
    # storage panel reads zero the moment the redirect lands.
    def purge_attachments(household, users)
      household.banner.purge

      users.each do |user|
        user.documents.find_each { |document| document.file.purge }
        user.photos.find_each { |photo| photo.image.purge }
        user.export_archive.purge
      end
    end

    # Sections (including user-created lenses, D25) and the error log are
    # instance-wide rather than household-scoped, so they can only be cleared
    # when the household that just went was the last one. The single-household
    # instance this button exists for hits that branch every time; a
    # multi-household box keeps its neighbours' hobbies.
    def clear_instance_leftovers
      return if Household.exists?

      Section.custom.destroy_all
      AppError.delete_all
      ActiveStorage::Blob.unattached.find_each(&:purge)
    end
  end
end
