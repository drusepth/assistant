module About
  # The /about tree (D-about-pages): static documentation of the software,
  # identical on every install, and the app's second unauthenticated read
  # path after /s/:token.
  #
  # It inherits that path's posture — its own bare layout, no session
  # chrome, no way further in — and adds the household switch. The switch
  # gates *anonymous* access only: a signed-in member always reads /about,
  # because turning off the public site should not delete the family's own
  # documentation.
  class BaseController < ApplicationController
    allow_unauthenticated_access
    skip_before_action :require_onboarding
    layout "about"

    # The same treatment the app's other public door gets. Nothing here is
    # expensive, but an open path with no ceiling is an open path with no
    # ceiling.
    rate_limit to: 120, within: 1.minute,
      with: -> { head :too_many_requests }

    before_action :require_public_pages

    private
      # A 404 rather than a 403: a 403 confirms the tree is there, which is
      # the one thing a household that turned it off is hiding.
      def require_public_pages
        return if authenticated? || Household.public_pages?

        raise ActionController::RoutingError, "Not Found"
      end

      # Every /about URL resolves through the registry (About::Page,
      # Tool::SLUGS), so an unrecognized slug never reaches a template
      # lookup. This is the one line standing between a wildcard route and
      # a file-read primitive — see docs/ABOUT_PLAN.md §5.
      def registered!(entry)
        entry || raise(ActionController::RoutingError, "Not Found")
      end

      # Hand-written prose, where a page has any. Hubs and tools render a
      # real page without it — generated cards, declared inputs — so the
      # waves that write the prose can land one page at a time instead of
      # all sixty at once. `slug` has already been through `registered!`.
      #
      # Slugs are hyphenated because URLs are; partial names can't be, so
      # `your-stuff` is served by `_your_stuff.html.erb`.
      def prose_for(directory, slug)
        name = slug.tr("-", "_")
        "about/#{directory}/#{name}" if lookup_context.exists?(name, [ "about/#{directory}" ], true)
      end
  end
end
