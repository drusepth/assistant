# Section taxonomy (D3, D12). Idempotent: safe to run in every environment.
[
  [ "health", "Health" ],
  [ "hobbies", "Hobbies" ],
  [ "education", "Education" ],
  [ "career", "Career" ],
  [ "people", "People" ],
  [ "money", "Money", {
    "budget" => "Budget",
    "debt" => "Debt",
    "taxes" => "Taxes",
    "assets" => "Assets",
    "bills" => "Bills",
    "subscriptions" => "Subscriptions",
    "benefits" => "Benefits"
  } ],
  [ "rights", "Rights", {
    "immigration" => "Immigration",
    "renting" => "Renting",
    "voting" => "Voting",
    "disputes" => "Disputes"
  } ],
  # The eighth section (D-travel-facet). Existing installs get it from
  # 20260823092731_add_travel_section.rb — keep the two in step.
  [ "travel", "Travel" ],
  # The ninth (D-pets-section): each pet's lens is a child of it. Existing
  # installs get it from 20260923060034_add_pets_section.rb.
  [ "pets", "Pets" ]
].each_with_index do |(slug, name, children), index|
  section = Section.find_or_initialize_by(slug: slug)
  section.update!(name: name, position: index + 1, parent: nil)

  (children || {}).each_with_index do |(child_slug, child_name), child_index|
    child = Section.find_or_initialize_by(slug: child_slug)
    child.update!(name: child_name, position: child_index + 1, parent: section)
  end
end
