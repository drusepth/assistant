# The Tools mode (D19): a Tool is a first-party pipeline — gather owned
# context, make one or a few LLM calls, land the result as draft primitives.
# Tools are code, not data (they're behavior, unlike the D12 taxonomy), and
# this explicit slug list is the whole registry: first-party only (D11).
module Tool
  SLUGS = %w[
    decode_letter dispute_letter insurance_appeal debt_collector_response
    deposit_demand results_explainer doctor_visit_prep
    find_care insurance_explainer compare_plans check_in start_a_practice
    negotiation_prep benefits_screener learn_something tutor quiz_me placement explain_this progress_report task_chat
    cancel_subscription reconnect gift_ideas get_together what_do_i_say make_new_friends moving
    build_my_budget money_coach spending_review debt_payoff_plan
    caregiver bereavement
    email_follow_up ask_your_email
    start_a_hobby what_should_i_make_next find_your_people
    interview_prep mock_interview check_pay_stub wage_claim tailor_application
    raise_case decode_offer lost_my_job plan_job_search
    find_my_next_move accommodation_request
    pet_care vet_visit_prep decode_vet_estimate compare_pet_insurance new_pet lost_pet
  ].freeze

  module_function

  def all = SLUGS.map { |slug| find(slug) }

  # The conversational tools (D29) — what /chats lists and filters by.
  def chat_slugs = all.select { |tool| tool.kind == :chat }.map(&:slug)

  def find(slug)
    const_get(slug.to_s.camelize) if SLUGS.include?(slug.to_s)
  end

  def find!(slug)
    find(slug) || raise(ActiveRecord::RecordNotFound, "no tool named #{slug.inspect}")
  end

  # Tools flow both ways along the taxonomy: one registered on a subsection
  # (rights → disputes) shows on the parent page too, and one registered on
  # a parent (hobbies) shows on every subsection page — user-created hobby
  # lenses (D25) can't be registered on ahead of time, so the Hobbies tools
  # belong on each hobby's page.
  def for_section(section)
    slugs = [ section.slug, section.parent&.slug, *section.children.map(&:slug) ].compact
    all.select { |tool| tool.section_slugs.intersect?(slugs) }
  end
end
