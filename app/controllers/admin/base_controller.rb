# Instance operations rather than household life: what the app is doing when
# nobody is watching. Gated on the household admin flag (D15) — on a fresh
# instance that is exactly the first-run user, but it keeps working if that
# account is ever removed and matches how Settings already gates membership.
module Admin
  class BaseController < ApplicationController
    before_action :require_admin
  end
end
