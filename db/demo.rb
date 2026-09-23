# The demo household — a fictional family, in enough detail that every
# surface in the app has something true-shaped on it.
#
# Run it with `bin/rails demo:seed` (never automatically, and never in
# production without saying so out loud — see lib/tasks/demo.rake).
#
# Why it exists: `docs/ABOUT_PLAN.md` §7. Every /about page wants
# screenshots, and real household data is private by definition, so the
# screenshots need a household that can be published. A fixture set built
# only for tests wouldn't do — it has no lore, and a screenshot of
# `Task one` sells nothing.
#
# The rule that makes it worth the trouble: **the lore crosses sections.**
# Danny's layoff is a Career record, a Money problem, a Health insurance
# question and a Rights claim for unpaid overtime, and it is the *same*
# event in all four places. That is the app's whole architectural argument,
# and a demo where each section held unrelated filler would quietly
# contradict it.
#
# Everything here is invented. Any resemblance to a real family, employer,
# or landlord is accidental.
module Demo
  PASSWORD = "demo-password-1234".freeze

  # Fixed anchors so the seed reads the same however long it has been since
  # it was written: the layoff is always ~7 weeks ago, the trip always next
  # month.
  TODAY = Date.current

  module_function

  def seed!
    reset!

    household = build_household

    # Every time in here is a wall-clock time in the family's kitchen, and
    # the app renders in the household's zone. Without this the seed parses
    # in the process default (UTC) and a 9am church service displays as 5am.
    Time.use_zone(household.zone) { populate(household) }
    household
  end

  def populate(household)
    kay, danny, ify = build_users(household)

    enable_sections(kay, danny, ify)
    people = build_people(kay, danny)
    pets = build_pets(kay, people)

    build_hobbies(kay, danny, ify)
    build_health(kay, danny, ify, people, pets)
    build_money(kay, danny)
    build_career(danny, kay)
    build_education(ify)
    build_rights(kay, danny)
    build_people_life(kay, people)
    build_recipes(kay, danny)
    build_reader(kay, danny, ify)
    build_photos(kay, danny, ify, people)
    build_travel(kay, danny, ify)
    build_vault(kay, danny)
    build_sharing(kay, danny)
  end

  # A rebuild rather than an upsert: this is demo data, and a half-updated
  # story is worse than a fresh one. Only ever touches the demo household.
  def reset!
    household = Household.find_by(name: household_name)
    return unless household

    # The mirror database has no foreign keys back to the primary, so its
    # rows have to go by hand — and before the users they name.
    SpendingTransaction.where(user_id: household.users.pluck(:id)).delete_all
    household.destroy!

    # Only now: a pet's lens is referenced by the pet, so custom sections
    # can't go until the household that owns those pets has.
    Section.where(custom: true).destroy_all
  end

  def household_name = "The Okafor–Lynch household"

  # ---------------------------------------------------------------- household

  def build_household
    Household.create!(
      name: household_name,
      tagline: "Prentice Street, and everyone in it",
      address: "418 Prentice Street\nApt 2\nMillbrook, OH 44432",
      phone: "(330) 555-0148",
      region: "Ohio, United States",
      currency: "USD",
      time_zone: "America/New_York",
      home_status: "rent",
      moved_in_on: Date.new(2019, 4, 12),
      public_pages_enabled: true
    )
  end

  def build_users(household)
    kay = household.users.create!(
      name: "Nkechi Okafor", email_address: "kay@example.com",
      password: PASSWORD, admin: true, onboarded_at: 2.years.ago,
      job_title: "Surgical scheduler", employer: "Mercy Regional Health"
    )
    danny = household.users.create!(
      name: "Danny Lynch", email_address: "danny@example.com",
      password: PASSWORD, onboarded_at: 2.years.ago,
      job_title: "HVAC technician", employer: "Kessler Mechanical (until July)"
    )
    ify = household.users.create!(
      name: "Ify Okafor-Lynch", email_address: "ify@example.com",
      password: PASSWORD, onboarded_at: 14.months.ago
    )

    [ kay, danny, ify ].each { |user| Keyring.initialize_for(user, PASSWORD) }
    [ kay, danny, ify ]
  end

  # Ify has no Money or Career section on; Danny has Education off. A demo
  # where everyone has everything switched on hides the fact that this is a
  # choice.
  def enable_sections(kay, danny, ify)
    off = { kay => [], danny => %w[ education ], ify => %w[ money career rights ] }

    [ kay, danny, ify ].each do |user|
      Section.top_level.each_with_index do |section, index|
        user.user_sections.create!(
          section: section, position: index + 1,
          enabled: off.fetch(user).exclude?(section.slug),
          agent_level: %w[ health money ].include?(section.slug) ? "active" : "quiet"
        )
      end
    end
  end

  # ------------------------------------------------------------------- people

  def build_people(kay, danny)
    people = {}

    people[:ada] = kay.people.create!(
      name: "Ada Okafor", relationship: "Mother", pronoun: "she", birthday: Date.new(1954, 3, 2),
      phone: "(330) 555-0193", address: "22 Halloway Court\nMillbrook, OH 44432",
      keep_in_touch: true, last_contacted_on: TODAY - 2,
      notes: "Mum. Fell in the kitchen in June — nothing broken, but she's slower and won't say so. " \
             "Cardiology at Mercy under Dr Adeyemi. Hates being fussed over; ask about the garden first. " \
             "Doesn't drive after dark any more, so any appointment after 4pm means I'm collecting her."
    )
    people[:colm] = kay.people.create!(
      name: "Colm Lynch", relationship: "Brother-in-law", pronoun: "he", birthday: Date.new(1979, 11, 8),
      phone: "+353 85 555 0112", keep_in_touch: true, last_contacted_on: TODAY - 41,
      notes: "Danny's brother, in Galway. Two kids — Saoirse (9) and Fintan (6). " \
             "Runs the family place since their dad died. Bad on email, fine on the phone Sunday evenings."
    )
    people[:marisol] = kay.people.create!(
      name: "Marisol Vega", relationship: "Best friend", pronoun: "she", birthday: Date.new(1982, 6, 19),
      phone: "(330) 555-0177", keep_in_touch: true, last_contacted_on: TODAY - 96,
      notes: "Nursing at Mercy with me for eleven years before she moved to the Cleveland job. " \
             "Coeliac — the brown bread is out, bring the almond thing. Her mother died in February and " \
             "I have been quietly rubbish about it since."
    )
    people[:hollis] = kay.people.create!(
      name: "Wendell Hollis", relationship: "Landlord", pronoun: "he", phone: "(330) 555-0102",
      email: "whollis@example.com",
      notes: "Owns the Prentice Street building. Fine in person, useless in writing. " \
             "Everything with him goes in an email afterwards — learned that the hard way over the boiler."
    )
    people[:adeyemi] = kay.people.create!(
      name: "Dr Funmi Adeyemi", relationship: "Mum's cardiologist", pronoun: "she", phone: "(330) 555-0166",
      notes: "Mercy Regional, cardiology. Sees Mum every six months. Wants the blood pressure log " \
             "brought to appointments — she asks for it every time and we forget it every time."
    )
    people[:pryor] = kay.people.create!(
      name: "Dr Sam Pryor", relationship: "Vet", phone: "(330) 555-0121",
      notes: "Millbrook Animal Hospital. Straight with you about cost, which is rarer than it should be."
    )
    people[:teresa] = kay.people.create!(
      name: "Teresa Okonjo", relationship: "Church", pronoun: "she", birthday: Date.new(1961, 9, 30),
      keep_in_touch: true, last_contacted_on: TODAY - 12,
      notes: "Runs the Sunday kitchen. Knew Mum before I was born. If anything is actually wrong " \
             "in this family she knows before I do."
    )
    people[:ruiz] = kay.people.create!(
      name: "Gabriel Ruiz", relationship: "Neighbour", pronoun: "he", phone: "(330) 555-0155",
      keep_in_touch: true, last_contacted_on: TODAY - 6,
      notes: "Apt 1, downstairs. Takes the bins out for us when we're away; we do his post. " \
             "Also had the deposit fight with Hollis in 2021 and won it — worth asking what he sent."
    )
    people[:bex] = kay.people.create!(
      name: "Bex Nakamura", relationship: "Ify's birding mentor", pronoun: "she",
      notes: "Runs the Saturday walks at Millbrook Reserve. Retired ornithologist, endlessly patient " \
             "with a fifteen-year-old asking the same question four ways. Ify would follow her off a cliff."
    )

    danny.people.create!(
      name: "Ray Kessler", relationship: "Former boss", pronoun: "he", phone: "(330) 555-0139",
      notes: "Ran Kessler Mechanical. Not a villain — the contract went and he cut four of us the same " \
             "Friday. Said he'd be a reference and I think he means it. Still owes me the overtime."
    )
    danny.people.create!(
      name: "Ahmed Farouk", relationship: "Union rep", pronoun: "he", phone: "(330) 555-0184",
      notes: "Local 47. Said to put the overtime claim in writing before the sixty days are up and to " \
             "copy him. Knows more about this than anyone I've met."
    )
    danny.people.create!(
      name: "Colm Lynch", relationship: "Brother", pronoun: "he", phone: "+353 85 555 0112",
      keep_in_touch: true, last_contacted_on: TODAY - 9,
      notes: "Galway. Rings on Sundays. Hasn't asked about the job once, which is his way of being kind."
    )

    people
  end

  # -------------------------------------------------------------------- pets

  def build_pets(kay, people)
    biscuit = kay.pets.create!(
      name: "Biscuit", species: "dog", breed: "Staffordshire terrier mix", sex: "female", neutered: true,
      color: "brindle and white", born_on: Date.new(2018, 5, 1), born_on_estimated: true,
      adopted_on: Date.new(2019, 6, 22), weight_lb: 38.4, microchip: "985141000284471",
      vet: people[:pryor], section: Pets::Lens.create!("Biscuit"),
      notes: "From Millbrook rescue, three months after we moved in. Terrified of the hoover and of " \
             "absolutely nothing else. Dr Pryor flagged grade 2 dental at the last visit — a clean under " \
             "anaesthetic is coming and it will not be cheap."
    )
    biscuit.pet_foods.create!(
      name: "Adult chicken & rice", brand: "Fieldmark", form: "dry",
      amount_per_day: 340, unit: "g", package_amount: 11_300, package_unit: "g",
      package_cost_cents: 5_499, started_on: TODAY - 400, opened_on: TODAY - 22,
      notes: "The only one that doesn't upset her stomach. Buy the big bag — the small one works out a third dearer."
    )

    sable = kay.pets.create!(
      name: "Sable", species: "cat", breed: "domestic shorthair", sex: "male", neutered: true,
      color: "black", born_on: Date.new(2013, 8, 15), born_on_estimated: true,
      adopted_on: Date.new(2014, 2, 1), weight_lb: 9.0, vet: people[:pryor],
      section: Pets::Lens.create!("Sable"),
      notes: "Twelve, and started losing weight in the spring. Bloods in August showed early kidney " \
             "trouble — on the prescription food now, which he resents. Drinks far more than he used to. " \
             "Sleeps on Ify's bed, has done since she was three."
    )
    sable.pet_foods.create!(
      name: "Renal support", brand: "Vetline", form: "wet",
      amount_per_day: 170, unit: "g", package_amount: 5_100, package_unit: "g",
      package_cost_cents: 8_240, started_on: TODAY - 46, opened_on: TODAY - 11,
      notes: "Prescription. Three times the price of the old food and there is no arguing with it."
    )

    { biscuit: biscuit, sable: sable }
  end

  # ----------------------------------------------------------------- hobbies

  def build_hobbies(kay, danny, ify)
    @hobbies = {
      bread: Hobbies::Lens.find_or_create!("Bread baking"),
      birding: Hobbies::Lens.find_or_create!("Birding"),
      motorcycles: Hobbies::Lens.find_or_create!("Motorcycles"),
      fishing: Hobbies::Lens.find_or_create!("Fishing")
    }

    kay.hobby_briefs.create!(
      section: @hobbies[:bread], authored_at: 8.months.ago,
      description: "Sourdough, mostly, since the first lockdown. One starter — Mum calls it the pet — fed " \
                   "Fridays. Trying to get an open crumb without the loaf going flat, which everyone online " \
                   "says is hydration and I think is my shaping."
    )
    ify.hobby_briefs.create!(
      section: @hobbies[:birding], authored_at: 5.months.ago,
      description: "Started at the reserve with Bex in April. 71 species on the life list. Currently obsessed " \
                   "with warblers, which everyone says is the hard place to start and that is exactly why."
    )
    danny.hobby_briefs.create!(
      section: @hobbies[:motorcycles], authored_at: 14.months.ago,
      description: "The '78 CB550 in the garage. Been 'nearly done' for two years. Carbs are off it at the moment."
    )

    kay.notes.create!(
      title: "The starter", body: "Fed Fridays, 1:1:1, rye and strong white. Named Bruce by Ify in 2020 " \
        "and it stuck. If it goes grey on top that's fine, pour it off. If it goes pink, it's gone — " \
        "start again from the dried backup in the freezer bag."
    ).tap { |note| tag(note, @hobbies[:bread], section("hobbies")) }

    ify.notes.create!(
      title: "Life list — new this year",
      body: "Prothonotary warbler (reserve boardwalk, 4 May, with Bex). Sora (heard only, 11 May — Bex says " \
        "heard counts, I'm counting it). Blackburnian (18 May, top of the oak by the car park, neck ache for " \
        "two days). Least bittern (2 Jun, still cannot believe it). Total 71."
    ).tap { |note| tag(note, @hobbies[:birding], section("hobbies")) }
  end

  # ------------------------------------------------------------------ health

  def build_health(kay, danny, ify, people, pets)
    health = section("health")
    people_s = section("people")

    kay.care_settings.create!(kind_key: "dental", interval_months: 6)
    kay.care_settings.create!(kind_key: "checkup", interval_months: 12)
    kay.care_settings.create!(kind_key: "vision", interval_months: 24)
    kay.care_settings.create!(kind_key: "mammogram", label: "Mammogram", interval_months: 12)
    danny.care_settings.create!(kind_key: "dental", interval_months: 6)
    danny.care_settings.create!(kind_key: "checkup", interval_months: 12)

    # Past care, so the radar has history to compute from.
    event(kay, "Dental cleaning", TODAY - 400, health, care_kind: "dental", location: "Millbrook Dental")
    event(kay, "Annual physical", TODAY - 300, health, care_kind: "checkup", location: "Dr Anand, Mercy Family")
    event(danny, "Dental cleaning", TODAY - 500, health, care_kind: "dental", location: "Millbrook Dental")

    # Upcoming.
    event(kay, "Mum — cardiology follow-up", TODAY + 9, health, people_s,
      at: "14:30", location: "Mercy Regional, Cardiology, 3rd floor",
      description: "Dr Adeyemi. BRING THE BLOOD PRESSURE LOG. Collecting Mum at 13:45 — she won't drive back in the dark.")
    event(kay, "Dental cleaning", TODAY + 23, health, at: "08:15", care_kind: "dental", location: "Millbrook Dental")
    event(ify, "Orthodontist — retainer check", TODAY + 16, health, at: "16:00")
    event(kay, "Biscuit — dental under anaesthetic", TODAY + 31, health, pets[:biscuit].section,
      at: "07:30", location: "Millbrook Animal Hospital",
      description: "Drop off 7:30, nil by mouth from midnight. Estimate was $840–$1,120 depending on extractions.")
    event(kay, "Sable — kidney bloods recheck", TODAY + 12, health, pets[:sable].section, at: "11:00")

    kay.notes.create!(
      title: "Mum's blood pressure log", kind: "plain",
      body: "Taken sitting, same chair, before breakfast.\n\n" \
            "Mon 138/84 · Tue 142/88 · Wed 136/82 · Thu 145/90 (had argued with the pharmacy) · " \
            "Fri 139/85 · Sat 133/81 · Sun 137/83\n\nDr Adeyemi asks for two weeks of this every time. " \
            "This is week one. Do not lose it again."
    ).tap { |n| tag(n, health, people_s) }

    kay.notes.create!(
      title: "What Dr Adeyemi said in June",
      body: "The fall wasn't cardiac — she's fairly sure it was the new blood pressure tablet dropping her " \
            "too far when she stood up. Halved the dose. Wants two weeks of readings before deciding whether " \
            "to change it entirely. Said the word 'orthostatic' four times and I finally asked what it meant: " \
            "blood pressure falling when you stand up. Nothing about her heart is worse than last year."
    ).tap { |n| tag(n, health, people_s) }

    ify.notes.create!(
      title: "Appendix — Nov 2023",
      body: "Keyhole, three nights in Mercy, home on the 19th. No complications. The scar is fine. " \
            "The bill was not fine — see the collections thing Mum is dealing with."
    ).tap { |n| tag(n, health) }

    # The list every new clinic's form asks for and nobody ever has ready.
    kay.notes.create!(kind: "medication", title: "Levothyroxine 75mcg",
      body: "Every morning, empty stomach, hour before food. Since 2016. Dr Anand reviews it each year.")
    kay.notes.create!(kind: "medication", title: "Sertraline 50mg", body: "Evenings, since 2022.")
    danny.notes.create!(kind: "medication", title: "Lisinopril 10mg", body: "Mornings. Blood pressure.")
    ify.notes.create!(kind: "allergy", title: "Penicillin", severity: "severe",
      body: "Rash and swelling at four years old. Flagged on the Mercy record; they used cefazolin " \
            "for the appendix without trouble.")
    ify.notes.create!(kind: "allergy", title: "Bee stings", severity: "moderate",
      body: "Local swelling, no breathing trouble. Carries antihistamines to the reserve.")
    kay.notes.create!(kind: "allergy", title: "Shellfish", severity: "mild", body: "Prawns only. Hives.")

    # Deliberately overdue: the dashboard's whole job is the things that
    # slipped, and a demo where nothing ever slips shows an empty panel.
    task(kay, "Ring the pharmacy about Mum's repeat prescription", TODAY - 3, health,
      section("people"), bucket: :today)
    task(kay, "Two weeks of Mum's BP readings before the 9th", TODAY + 8, health, bucket: :today)
    task(kay, "Ask Dr Pryor whether Sable's food can be split into smaller bags", TODAY + 12, health)
    task(danny, "Book the dentist — it's been 16 months", nil, health)
  end

  # ------------------------------------------------------------------- money

  def build_money(kay, danny)
    money = section("money")
    budget = section("budget")

    account = kay.spending_accounts.create!(name: "Huntington joint checking", kind: "checking", last4: "4412")
    card = kay.spending_accounts.create!(name: "Capital One card", kind: "credit", last4: "8830")

    groups = {
      "Rent" => [ 118_000, "needs" ], "Groceries" => [ 78_000, "needs" ],
      "Utilities" => [ 24_000, "needs" ], "Petrol & car" => [ 22_000, "needs" ],
      "Health & pharmacy" => [ 18_000, "needs" ], "Pets" => [ 14_000, "needs" ],
      "Phone & internet" => [ 12_500, "needs" ], "Insurance" => [ 31_000, "needs" ],
      "Debt payments" => [ 26_000, "savings_debt" ], "Eating out" => [ 12_000, "wants" ],
      "Ify — school & books" => [ 9_000, "wants" ], "Subscriptions" => [ 4_800, "wants" ],
      "Church & giving" => [ 8_000, "wants" ], "Savings" => [ 15_000, "savings_debt" ]
    }
    categories = {}
    groups.each_with_index do |(name, (target, group)), index|
      categories[name] = kay.budget_categories.create!(
        name: name, monthly_target_cents: target, group: group,
        position: index + 1, target_set_by: "user"
      )
    end

    rules = {
      "Kroger" => "Groceries", "Aldi" => "Groceries", "Speedway" => "Petrol & car",
      "Ohio Edison" => "Utilities", "Millbrook Animal" => "Pets", "Netflix" => "Subscriptions",
      "Spotify" => "Subscriptions", "CVS" => "Health & pharmacy", "Hollis Property" => "Rent"
    }
    rules.each { |matcher, category| kay.spending_rules.create!(matcher: matcher, budget_category: categories.fetch(category)) }

    ledger(kay, account, card, categories)

    kay.notes.create!(
      title: "The September problem",
      body: "Danny's last full paycheck was 18 July. Unemployment is $431/wk and started the 5th of August, " \
            "which is $1,724 a month against his $3,180. We are $1,456 short every month.\n\n" \
            "Cut so far: Netflix (gone), the meal box (gone), eating out down to once. That is $214. " \
            "The rest has to come out of savings, which lasts until roughly February, or the job comes first.\n\n" \
            "Not touching: Ify's books, church, or Sable's food."
    ).tap { |n| tag(n, money, budget) }

    kay.notes.create!(
      title: "Debts, written down properly",
      body: "Mercy Regional — Ify's appendix, balance after insurance $2,140, no interest, now with Ardent " \
            "Recovery (see Rights).\nCapital One — $3,880 at 26.99%. This is the expensive one.\n" \
            "Honda — $6,220 at 5.9%, $268/mo, 24 payments left.\nStudent loan (mine) — $9,410 at 4.5%, " \
            "$118/mo.\n\nOrder: Capital One first, obviously. But nothing extra goes anywhere until Danny's working."
    ).tap { |n| tag(n, money, section("debt")) }

    # Money's seven subsections are tiles on the section page, and a demo
    # with all seven empty makes the taxonomy look decorative.
    kay.notes.create!(
      title: "Everything we pay monthly, and what happened to it",
      body: "Netflix $15.49 — cancelled 4 August.\nMeal box $61.99 — cancelled 3 August.\n" \
            "Spotify $11.99 — kept. Ify uses it for the practice tracks and it is eleven dollars.\n" \
            "Spectrum $89 — rang them, they will do $69 for twelve months if I re-sign. Do it.\n" \
            "Verizon $36 — two lines, out of contract, worth shopping.\n" \
            "Amazon $14.99 — nobody in this house knows why we have this."
    ).tap { |n| tag(n, money, section("subscriptions")) }

    kay.notes.create!(
      title: "The bills, and when they actually land",
      body: "Rent — 1st, $1,180, Hollis Property.\nOhio Edison — 6th, budget billing would even this out.\n" \
            "Millbrook Water — 6th, quarterly, about $41 a month equivalent.\n" \
            "Spectrum + Verizon — 11th.\nHonda — 15th, $268, 24 payments left.\n" \
            "Ohio Mutual (car) — 28th, renews 22 Sep."
    ).tap { |n| tag(n, money, section("bills")) }

    kay.notes.create!(
      title: "What we actually own",
      body: "2016 Honda CR-V — 118k miles, $6,220 still owing on it, worth maybe $9,500.\n" \
            "Danny's '78 CB550 — worth more in parts than assembled, which he will not hear.\n" \
            "My 403(b) at Mercy — $31,400, 4% with a 3% match. Do not touch this.\n" \
            "Emergency fund — $4,180. This is the number I watch."
    ).tap { |n| tag(n, money, section("assets")) }

    kay.notes.create!(
      title: "Tax notes for next year",
      body: "Danny's unemployment is taxable and they are NOT withholding by default — I ticked the box in " \
            "August but the first six weeks came gross. Set aside roughly 10%.\n\n" \
            "Ify's homeschool materials are not deductible in Ohio. Checked twice, still annoying.\n\n" \
            "Mercy's premiums come out pre-tax, so the W-2 box 1 will look lower than what I think I earn."
    ).tap { |n| tag(n, money, section("taxes")) }

    task(kay, "Set aside 10% of Danny's unemployment for tax", TODAY + 6, money, section("taxes"))
    task(kay, "Re-sign Spectrum at the $69 rate", TODAY + 5, money, section("subscriptions"), bucket: :today)
    task(kay, "Screen for the utility credit and the EITC", TODAY + 15, money, section("benefits"))
    task(kay, "Ring Honda about deferring one payment", TODAY + 8, money, section("debt"))
    event(kay, "Ohio Edison bill", TODAY + 9, money, section("bills"), all_day: true)

    task(kay, "Cancel the meal box before the 3rd", TODAY - 4, money, done: TODAY - 5)
    task(kay, "Ring Ohio Edison about the budget billing plan", TODAY + 3, money, bucket: :today)
    task(kay, "Check whether Ify qualifies for the reduced-price lab fees", TODAY + 20, money)

    event(kay, "Rent due", TODAY.next_month.change(day: 1), money, all_day: true)
    event(kay, "Car insurance renews", TODAY + 26, money, all_day: true,
      description: "$1,142 for six months last time. Shop it — Gabriel says he moved and saved $300.")
    event(danny, "Unemployment claim — weekly certification", TODAY + 2, money, all_day: true)

    goal(kay, "Get through to February without touching the emergency fund", money,
      "Danny's unemployment plus my wage is $1,456/mo short. Close the gap without cutting Ify's " \
      "books or Sable's food.", TODAY + 150,
      [ [ "Move the car insurance — get three quotes", TODAY + 20 ],
        [ "Ask Hollis about paying rent on the 5th instead of the 1st", TODAY + 9 ],
        [ "Apply for the utility hardship rate", TODAY + 14 ],
        [ "Sell the CB550 parts Danny's not using", nil ] ])
  end

  # Three months of a real-shaped month: rent, the shop, petrol, the small
  # leaks. Deterministic — a demo whose numbers move every reseed makes the
  # screenshots unrepeatable.
  def ledger(kay, account, card, categories)
    rows = [
      [ "Hollis Property Mgmt", "Rent", -118_000, 1, account ],
      [ "Kroger", "Groceries", -14_240, 3, account ],
      [ "Speedway", "Petrol & car", -4_180, 4, card ],
      [ "Ohio Edison", "Utilities", -11_840, 6, account ],
      [ "Millbrook Water", "Utilities", -4_120, 6, account ],
      [ "CVS Pharmacy", "Health & pharmacy", -3_460, 7, card ],
      [ "Aldi", "Groceries", -8_910, 9, account ],
      [ "Spectrum", "Phone & internet", -8_900, 11, account ],
      [ "Verizon", "Phone & internet", -3_600, 11, account ],
      [ "Millbrook Animal Hospital", "Pets", -9_800, 12, card ],
      [ "Kroger", "Groceries", -16_720, 14, account ],
      [ "Honda Financial", "Debt payments", -26_800, 15, account ],
      [ "Speedway", "Petrol & car", -3_940, 16, card ],
      [ "St Brigid's", "Church & giving", -8_000, 17, account ],
      [ "Spotify", "Subscriptions", -1_199, 18, card ],
      [ "Netflix", "Subscriptions", -1_549, 19, card ],
      [ "Aldi", "Groceries", -11_330, 21, account ],
      [ "Vetline Direct", "Pets", -8_240, 22, card ],
      [ "Gino's", "Eating out", -4_260, 23, card ],
      [ "Kroger", "Groceries", -13_880, 27, account ],
      [ "Speedway", "Petrol & car", -4_010, 28, card ],
      [ "Ohio Mutual Insurance", "Insurance", -19_030, 28, account ]
    ]
    income = [ [ "Mercy Regional Health — payroll", 214_600, 15 ], [ "Mercy Regional Health — payroll", 214_600, 30 ] ]

    (0..2).each do |months_ago|
      month = TODAY.beginning_of_month << months_ago

      rows.each do |merchant, category, cents, day, source|
        # The story has to show in the numbers: the meal box and Netflix stop
        # after the layoff, and eating out halves.
        next if merchant == "Netflix" && months_ago.zero?

        occurred = month.change(day: [ day, month.end_of_month.day ].min)
        cents = (cents * 0.5).round if merchant == "Gino's" && months_ago.zero?

        SpendingTransaction.create!(
          user_id: kay.id, spending_account_id: source.id,
          budget_category_id: categories.fetch(category).id, categorized_by: "rule",
          merchant: merchant, descriptor: merchant.upcase, amount_cents: cents,
          occurred_on: occurred, source: "statement",
          fingerprint: "demo-#{source.id}-#{occurred}-#{cents}-#{merchant.parameterize}"
        )
      end

      income.each do |merchant, cents, day|
        occurred = month.change(day: [ day, month.end_of_month.day ].min)
        SpendingTransaction.create!(
          user_id: kay.id, spending_account_id: account.id, merchant: merchant,
          descriptor: merchant.upcase, amount_cents: cents, occurred_on: occurred,
          source: "statement", fingerprint: "demo-pay-#{occurred}-#{cents}"
        )
      end

      # Danny's wage stops after July; unemployment starts a fortnight later.
      if months_ago >= 2
        occurred = month.change(day: 20)
        SpendingTransaction.create!(
          user_id: kay.id, spending_account_id: account.id, merchant: "Kessler Mechanical — payroll",
          descriptor: "KESSLER MECHANICAL", amount_cents: 318_000, occurred_on: occurred,
          source: "statement", fingerprint: "demo-kessler-#{occurred}"
        )
      else
        [ 7, 14, 21, 28 ].each do |day|
          occurred = month.change(day: day)
          SpendingTransaction.create!(
            user_id: kay.id, spending_account_id: account.id, merchant: "Ohio Dept of Job & Family Services",
            descriptor: "ODJFS BENEFIT", amount_cents: 43_100, occurred_on: occurred,
            source: "statement", fingerprint: "demo-ui-#{occurred}"
          )
        end
      end
    end
  end

  # ------------------------------------------------------------------ career

  def build_career(danny, kay)
    career = section("career")
    money = section("money")

    danny.job_feeds.create!(url: "https://example.org/jobs/hvac-northeast-ohio.rss",
      label: "HVAC — Northeast Ohio", last_scanned_at: 6.hours.ago)
    danny.job_feeds.create!(url: "https://example.org/jobs/millbrook-trades.rss",
      label: "Millbrook & Canton trades", last_scanned_at: 6.hours.ago)

    danny.notes.create!(
      title: "What actually happened, for the record",
      body: "Friday 18 July. Ray called four of us in one at a time. The Sheffler contract went and with it " \
            "about a third of the commercial work. Not performance — he said so twice and put it in the letter, " \
            "which Ahmed says matters for the claim.\n\n" \
            "Eleven years. EPA 608 Universal, and the NATE cert I did in 2021.\n\n" \
            "Final cheque was short. Two weeks of the overtime from the Sheffler shutdown in June — 22 hours " \
            "at time and a half. I have the sign-in sheets photographed."
    ).tap { |n| tag(n, career, money) }

    danny.notes.create!(
      title: "Wins, kept as they happened",
      body: "— Rebuilt the Sheffler rooftop units over the June shutdown, 22 hrs overtime, no callbacks since.\n" \
            "— Trained Marco and Dee on the new refrigerant handling. Ray asked me to, not the other way round.\n" \
            "— Cut the callback rate on my installs to about one in twenty over 2024; the shop average was nearer one in eight.\n" \
            "— Held the on-call phone every third weekend for four years.\n" \
            "— NATE certification, 2021, paid for it myself."
    ).tap { |n| tag(n, career) }

    danny.notes.create!(
      title: "What I'm actually looking for",
      body: "Commercial HVAC, service side rather than install if I can get it — the install work is hard on " \
            "my back now. Within 40 minutes of Millbrook because of Mum and Ify. $32/hr is what I was on; " \
            "Ahmed reckons the market is $34–38 for someone with the 608 and eleven years, but I need to check " \
            "that rather than repeat it in a room. Would take $30 with real benefits."
    ).tap { |n| tag(n, career) }

    goal(danny, "Get back to work by November", career,
      "Eleven years commercial HVAC. Service side preferred, within 40 minutes, $32/hr or the equivalent in benefits.",
      TODAY + 60,
      [ [ "Get the 608 card reissued — can't find the original", TODAY - 10, TODAY - 8 ],
        [ "Rewrite the resume around the Sheffler work", TODAY - 3, TODAY - 2 ],
        [ "Ask Ray for the reference in writing", TODAY + 1 ],
        [ "Four applications a week — this week's", TODAY + 4 ],
        [ "Ring Ahmed about the apprenticeship instructor opening", TODAY + 6 ],
        [ "Check what service techs are actually paid in Stark County", TODAY + 9 ] ])

    task(danny, "Chase Bellamy Mechanical — applied 12 days ago, no reply", TODAY + 1, career, bucket: :today)
    task(danny, "Practice the 'why did you leave' answer out loud", TODAY + 2, career, bucket: :today)

    event(danny, "Interview — Bellamy Mechanical (service tech)", TODAY + 5, career,
      at: "10:00", location: "2200 Wexford Ave, Canton",
      description: "Second round. Bring the 608 card, the NATE cert, and the Sheffler photos. Ask about the on-call rota.")
    event(danny, "Union hall — apprenticeship instructor info session", TODAY + 13, career, at: "18:30")

    kay.notes.create!(
      title: "Insurance if Danny doesn't have a job by December",
      body: "We're on my Mercy plan, so nothing changes while I'm working there — that's the one piece of luck " \
            "in this. If I ever leave, COBRA was quoted at $1,840/mo which is not a real number for us; the " \
            "marketplace with the income we'd have then was nearer $310 with the credit. Worth knowing before " \
            "it's urgent rather than during."
    ).tap { |n| tag(n, section("health"), money, career) }
  end

  # --------------------------------------------------------------- education

  def build_education(ify)
    education = section("education")

    ify.notes.create!(
      title: "Why we're homeschooling",
      body: "Pulled out of Millbrook High in January 2024, halfway through year 9. It wasn't one thing — the " \
            "anxiety got bad, the maths class was 34 kids and she'd already stopped putting her hand up, and " \
            "after the appendix she missed five weeks and nobody noticed she hadn't caught up.\n\n" \
            "Ohio notification filed with the district each August. Portfolio route, not the test route."
    ).tap { |n| tag(n, education) }

    algebra = ify.subjects.create!(
      title: "Algebra I", status: 1, tree_built_at: 13.months.ago, commons_key: "math.algebra-1",
      description: "The one she was behind on and the reason for a lot of this.",
      interest_frame: "Bird counts and survey data — she'll do any amount of algebra if the numbers are warblers.",
      target_date: TODAY + 120
    )
    topics(algebra, [
      [ "Variables and expressions", 3, TODAY - 300, "quiz" ],
      [ "Solving linear equations", 3, TODAY - 250, "quiz" ],
      [ "Inequalities", 3, TODAY - 190, "teach_back" ],
      [ "Graphing lines", 3, TODAY - 120, "teach_back" ],
      [ "Systems of equations", 2, nil, nil ],
      [ "Exponents and radicals", 1, nil, nil ],
      [ "Quadratics", 0, nil, nil ],
      [ "Polynomials", 0, nil, nil ]
    ])

    biology = ify.subjects.create!(
      title: "Biology", status: 1, tree_built_at: 9.months.ago, commons_key: "science.biology",
      description: "Her own idea. Started because of the birding and got away from both of us.",
      interest_frame: "Ornithology throughout — migration, plumage, the reserve's own survey data."
    )
    topics(biology, [
      [ "Cells and organelles", 3, TODAY - 200, "quiz" ],
      [ "Genetics and inheritance", 3, TODAY - 140, "teach_back" ],
      [ "Evolution and natural selection", 3, TODAY - 90, "tutor" ],
      [ "Ecology and populations", 2, nil, nil ],
      [ "Classification and taxonomy", 2, nil, nil ],
      [ "Human body systems", 0, nil, nil ]
    ])

    history = ify.subjects.create!(
      title: "US History", status: 1, tree_built_at: 7.months.ago, commons_key: "social.us-history",
      description: "The one she does because she has to. Goes better when it's local."
    )
    topics(history, [
      [ "Colonial period", 3, TODAY - 160, "teach_back" ],
      [ "Revolution and founding", 3, TODAY - 110, "quiz" ],
      [ "Civil War and Reconstruction", 2, nil, nil ],
      [ "Industrialisation", 1, nil, nil ],
      [ "Civil rights movement", 0, nil, nil ]
    ])

    # Review queue: some due today, some ahead, so the page has both states.
    [ [ algebra, "Graphing lines", "What does the slope of a line represent?",
        "The rate of change — how much y moves for each unit of x.", -1 ],
      [ algebra, "Solving linear equations", "Solve: 3x + 7 = 22", "x = 5", 0 ],
      [ algebra, "Inequalities", "What happens to the sign when you multiply an inequality by a negative?",
        "It flips.", 0 ],
      [ biology, "Genetics and inheritance", "What is the difference between genotype and phenotype?",
        "Genotype is the genetic makeup; phenotype is the observable characteristics it produces.", 2 ],
      [ biology, "Evolution and natural selection", "Why does a trait spread through a population?",
        "Because individuals carrying it leave more surviving offspring than those without it.", 5 ],
      [ history, "Revolution and founding", "What did the Northwest Ordinance of 1787 establish?",
        "How territories became states, and it barred slavery in the Northwest Territory.", 9 ]
    ].each do |subject, topic_title, prompt, answer, due_in|
      topic = subject.topics.find_by!(title: topic_title)
      ify.review_items.create!(
        topic: topic, prompt: prompt, answer: answer, kind: 0, state: 2,
        due_at: (TODAY + due_in).to_time.change(hour: 9), reps: 4, lapses: due_in.negative? ? 1 : 0,
        stability: 12.4, difficulty: 5.2, last_reviewed_at: (TODAY - 14).to_time
      )
    end

    # Six weeks of study, so the hours log has something honest in it.
    42.downto(0) do |days_ago|
      day = TODAY - days_ago
      next if day.saturday? || day.sunday?

      [ [ algebra, 45, 0 ], [ biology, 40, 1 ], [ history, 30, 0 ] ].each_with_index do |(subject, minutes, activity), index|
        next unless (day.yday + index) % 2 == 0

        ify.study_logs.create!(subject: subject, on: day, minutes: minutes, activity: activity,
          note: index.zero? ? nil : "Reserve survey data again — she is not bored of it yet")
      end
    end

    event(ify, "Reserve bird survey with Bex", TODAY + 3, education, @hobbies[:birding],
      at: "07:00", location: "Millbrook Reserve, boardwalk car park")
    event(ify, "Portfolio review with Mum", TODAY + 27, education, all_day: true)
    task(ify, "Finish the systems-of-equations set", TODAY + 2, education, bucket: :today)
    task(ify, "Write up the September survey counts", TODAY + 5, education)
  end

  def topics(subject, rows)
    rows.each_with_index do |(title, mastery, mastered_on, evidence), index|
      subject.topics.create!(title: title, position: index + 1, mastery: mastery,
        mastered_on: mastered_on, mastery_evidence: evidence)
    end
  end

  # ------------------------------------------------------------------ rights

  def build_rights(kay, danny)
    rights = section("rights")
    renting = section("renting")
    disputes = section("disputes")
    money = section("money")

    kay.notes.create!(
      title: "Ardent Recovery — the letter that came on the 12th",
      body: "$2,140 for Ify's appendix in November 2023. Mercy's billing said this was settled with insurance " \
            "in March.\n\nAhmed's wife had this and said the same thing Gabriel did: do not ring them, do not " \
            "acknowledge the debt, send a written validation request inside 30 days. The letter is dated the 8th, " \
            "so the window closes on the 7th of next month.\n\nWhat I actually think happened: the insurer paid " \
            "the surgeon and not the facility, and nobody at Mercy chased it."
    ).tap { |n| tag(n, rights, disputes, money) }

    kay.notes.create!(
      title: "The boiler, and everything I've sent about it",
      body: "Out for nine days in February. Hollis said 'this week' four times.\n\n" \
            "3 Feb — reported by phone.\n7 Feb — first email (kept).\n11 Feb — second email, said we'd been " \
            "boiling water for the bath for a week.\n12 Feb — fixed.\n\nGabriel says the same thing happened " \
            "upstairs in 2021 and that Hollis kept $600 of his deposit for 'cleaning' with no itemised list, " \
            "and that a single formal letter got it back inside three weeks. Lease is up in April. " \
            "Photograph everything before we go."
    ).tap { |n| tag(n, rights, renting) }

    danny.notes.create!(
      title: "The overtime Kessler still owes",
      body: "22 hours at time and a half from the Sheffler shutdown, 9–20 June. $32/hr base, so $1,056.\n\n" \
            "Evidence: the sign-in sheets (photographed, all six days), the shutdown schedule Ray emailed on " \
            "6 June, and Marco will say he was there because he was.\n\nAhmed: put it in writing to Ray first, " \
            "certified, give him 14 days, then the state wage claim. Sixty days from the final cheque, which was " \
            "1 August. Deadline is 30 September."
    ).tap { |n| tag(n, rights, section("career"), money) }

    # Rights has four subsections too; Immigration and Voting are real parts
    # of this family's year even though nothing is going wrong in them.
    kay.notes.create!(
      title: "Mum's citizenship papers — where they are",
      body: "Ada naturalised in 1991. Certificate is in the grey box on top of my wardrobe, not at hers — " \
            "she asked me to keep it after the fall.\n\nDanny is a US citizen by birth but holds an Irish " \
            "passport too, through his father. Renewed 2023, good until 2033. Ify has both; hers needs doing " \
            "before the Galway trip whenever that next happens."
    ).tap { |n| tag(n, rights, section("immigration")) }

    kay.notes.create!(
      title: "Voting — Millbrook, precinct 4",
      body: "Polling place moved in 2024 from the school to the fire station on Halloway. Ada's absentee " \
            "ballot request has to go in every year, she always forgets, remind her in September.\n\n" \
            "Ify turns 18 in two years and can pre-register at 17."
    ).tap { |n| tag(n, rights, section("voting")) }

    task(kay, "Remind Mum to request her absentee ballot", TODAY + 11, rights, section("voting"))
    task(kay, "Renew Ify's Irish passport before it expires", TODAY + 60, rights, section("immigration"))

    task(kay, "Send the Ardent validation letter — certified", TODAY + 4, rights, disputes, bucket: :today)
    task(danny, "Send the overtime demand to Ray, certified, copy Ahmed", TODAY + 3, rights, bucket: :today)
    task(kay, "Photograph every room before the lease ends", TODAY + 40, rights, renting)
    task(kay, "Ask Gabriel for a copy of the letter he sent Hollis", TODAY + 2, rights, renting, bucket: :today)

    event(kay, "Ardent validation window closes", TODAY + 10, rights, disputes, all_day: true,
      description: "30 days from the letter dated the 8th. After this it is much harder to make them prove it.")
    event(danny, "Wage claim deadline — 60 days from final cheque", TODAY + 18, rights, all_day: true)
  end

  # ------------------------------------------------------------------- people

  def build_people_life(kay, people)
    people_s = section("people")

    event(kay, "Mum's birthday", Date.new(TODAY.year + (TODAY.month > 3 ? 1 : 0), 3, 2), people_s, all_day: true)
    event(kay, "Sunday kitchen — St Brigid's", TODAY + 4, people_s, at: "09:00")
    event(kay, "Marisol — coffee, finally", TODAY + 11, people_s, at: "15:00", location: "Bramble, Canton")

    task(kay, "Sort something for Teresa's 65th", TODAY + 25, people_s)

    kay.notes.create!(
      title: "Marisol — what I keep not saying",
      body: "Her mother died on the 14th of February and I sent one message and then let three months go by " \
            "because I didn't know what to say and then it felt too late to say anything.\n\n" \
            "It is not too late. Say that I've been thinking about her, that I'm sorry I went quiet, and ask " \
            "about her mother by name — Elena. People want to hear the name."
    ).tap { |n| tag(n, people_s) }

    goal(kay, "Stop letting the people I love drift", people_s,
      "Marisol, Colm, and Teresa. Not a system — three specific conversations.", TODAY + 45,
      [ [ "Ring Marisol", TODAY + 1 ],
        [ "Sunday call to Colm and actually ask about the farm", TODAY + 4 ],
        [ "Take Teresa the sourdough she keeps asking about", TODAY + 8 ] ])
  end

  # ----------------------------------------------------------------- recipes

  def build_recipes(kay, danny)
    jollof = recipe(kay, "Mum's jollof rice", servings: 6, prep: 25, cook: 55, cooked: 31,
      last: TODAY - 12, favorite: true,
      description: "Ada's, exactly as she makes it, written down the Christmas she said she wasn't going to be " \
                   "cooking forever. The blended pepper base is the whole thing.",
      ingredients: "3 red bell peppers\n2 plum tomatoes\n1 scotch bonnet, seeds out unless Danny is away\n" \
                   "1 large onion\n120ml groundnut oil\n3 tbsp tomato puree\n500g long-grain parboiled rice\n" \
                   "700ml chicken stock\n2 tsp curry powder\n1 tsp dried thyme\n2 bay leaves\nSalt",
      directions: "Blend the peppers, tomatoes, scotch bonnet and half the onion until smooth.\n\n" \
                  "Slice the rest of the onion and soften it in the oil. Add the puree and fry it until it darkens " \
                  "— four or five minutes, longer than feels right.\n\nPour in the blend and cook it down until the " \
                  "oil comes back to the top. This is the part everyone rushes. Twenty minutes at least.\n\n" \
                  "Stir in the spices, then the rinsed rice, then the stock. Cover with foil under the lid and cook " \
                  "on the lowest heat for 30 minutes. Do not lift the lid.\n\nLet it catch very slightly at the " \
                  "bottom at the end. That's the good bit and Mum will deny she does it.",
      notes: "Mum's version has no curry powder and she has never admitted why mine tastes different.")

    bread = recipe(kay, "Bruce — the Friday sourdough", servings: 2, prep: 40, cook: 45, cooked: 88,
      last: TODAY - 3, favorite: true,
      description: "The weekly loaf. 78% hydration, which is as far as I can push it before shaping falls apart.",
      ingredients: "800g strong white flour\n200g wholemeal\n780g water\n200g active starter\n20g salt",
      directions: "Autolyse flour and 700g of the water, one hour.\n\nAdd starter and salt with the last 80g of " \
                  "water. Four sets of stretch and folds, 30 minutes apart.\n\nBulk until roughly 50% risen — " \
                  "about 4.5 hours at 22°C in this kitchen, less in summer.\n\nPreshape, 20 minutes, shape tight. " \
                  "Fridge overnight.\n\n250°C in the Dutch oven, 20 minutes lid on, 22 off.",
      notes: "Flat loaves are always my shaping, never the hydration. Tighter preshape.")

    brown = recipe(danny, "Nan Lynch's brown bread", servings: 1, prep: 10, cook: 50, cooked: 14,
      last: TODAY - 40,
      description: "Galway. Takes ten minutes and there is no yeast and no waiting, which Kay finds offensive.",
      ingredients: "400g coarse wholemeal\n100g plain flour\n1 tsp bicarbonate of soda\n1 tsp salt\n" \
                   "450ml buttermilk\n1 tbsp treacle",
      directions: "Oven to 200°C. Mix the dry. Stir in the buttermilk and treacle until it just comes together — " \
                  "do not knead it, it is not that kind of bread.\n\nInto a greased loaf tin. 50 minutes. " \
                  "Hollow when you knock the bottom.\n\nCool it on a rack or the middle goes gluey.",
      notes: "Nan used the treacle; Colm swears she didn't. She did.")

    egusi = recipe(kay, "Egusi soup", servings: 6, prep: 20, cook: 60, cooked: 9, last: TODAY - 55,
      description: "For when Mum comes on a Sunday.",
      ingredients: "200g ground egusi (melon seed)\n500g goat or beef, bone in\n2 handfuls chopped spinach\n" \
                   "1 onion\n3 tbsp palm oil\n2 tbsp ground crayfish\n1 scotch bonnet\n2 stock cubes\nSalt",
      directions: "Boil the meat with half the onion and a stock cube until tender, keep the liquor.\n\n" \
                  "Heat the palm oil, fry the rest of the onion, add the egusi paste and let it fry in lumps " \
                  "without stirring for ten minutes.\n\nAdd the liquor a ladle at a time, then the crayfish, " \
                  "pepper and meat. Simmer 25 minutes.\n\nSpinach in at the very end.")

    [ [ "Sheet-pan sausages and peppers", danny, "The Tuesday one. No thinking required." ],
      [ "Ify's banana bread", kay, "Made when the bananas go. She does it herself now." ],
      [ "Chin chin", kay, "Christmas and church. Doubles easily; never lasts." ] ].each do |title, owner, description|
      recipe(owner, title, servings: 4, prep: 15, cook: 35, cooked: 6, last: TODAY - 70,
        description: description, ingredients: "See the card in the tin", directions: "See the card in the tin")
    end

    book = kay.recipe_books.create!(
      title: "Mum's, before we lose them", cover_recipe: jollof,
      description: "Written down over two Christmases because Ada cooks by memory and none of it was anywhere. " \
                   "Ify gets a copy of this whatever else happens."
    )
    [ jollof, egusi ].each_with_index { |r, i| book.recipe_book_entries.create!(recipe: r, position: i + 1) }

    weekly = kay.recipe_books.create!(title: "What we actually eat",
      description: "The rotation. Nothing in here takes more than an hour on a weeknight.")
    [ bread, brown ].each_with_index { |r, i| weekly.recipe_book_entries.create!(recipe: r, position: i + 1) }

    # Ada has no account anywhere and never will; the link is how she gets
    # her own recipes back.
    kay.share_links.create!(subject: book, label: "For Mum and Aunty Chi",
      views_count: 6, last_viewed_at: 3.days.ago)
  end

  def recipe(user, title, ingredients:, directions:, servings:, prep:, cook:, cooked:, last:,
             description: nil, notes: nil, favorite: false)
    user.recipes.create!(
      title: title, description: description, notes: notes, servings: servings,
      prep_minutes: prep, cook_minutes: cook, times_cooked: cooked, last_cooked_on: last,
      favorite: favorite, ingredients_text: ingredients, directions: directions
    )
  end

  # ------------------------------------------------------------------ reader

  def build_reader(kay, danny, ify)
    feeds = [
      [ ify, "Millbrook Reserve — sightings", "https://example.org/millbrook/sightings.xml", @hobbies[:birding], false,
        [ [ "Least bittern still present on the north pool", 1 ],
          [ "Warbler wave overnight — 14 species logged before 9am", 3 ],
          [ "Boardwalk closed Thursday for repairs", 6 ] ] ],
      [ ify, "American Birding Association", "https://example.org/aba/feed.xml", @hobbies[:birding], false,
        [ [ "How to tell a Blackpoll from a Bay-breasted in autumn", 2 ],
          [ "The 2026 Big Year rules have changed", 8 ] ] ],
      [ kay, "The Sourdough Journal", "https://example.org/sourdough/feed.xml", @hobbies[:bread], false,
        [ [ "Why your open crumb is a shaping problem, not a hydration one", 1 ],
          [ "Rye starters through a cold kitchen", 5 ] ] ],
      [ danny, "HVAC School", "https://example.org/hvacschool/feed.xml", nil, false,
        [ [ "A2L refrigerants: what changes for service techs this year", 2 ],
          [ "Diagnosing a failing TXV without pulling the unit", 7 ] ] ],
      [ kay, "Millbrook Herald", "https://example.org/herald/feed.xml", nil, true,
        [ [ "County commissioners approve the Prentice Street rezoning", 1 ],
          [ "Mercy Regional cuts overnight paediatric hours", 2 ],
          [ "Reserve wins state grant for boardwalk repair", 4 ],
          [ "Kessler Mechanical lays off nine as Sheffler contract ends", 52 ] ] ]
    ]

    feeds.each do |user, title, url, hobby, broad, items|
      feed = user.feeds.create!(
        url: url, title: title, site_url: url.sub(%r{/[^/]+\.xml\z}, ""), active: true,
        broad: broad, classified_at: 30.days.ago, last_fetched_at: 2.hours.ago,
        last_item_at: (TODAY - items.map(&:last).min).to_time, description: "Demo feed — nothing is fetched."
      )
      tag(feed, hobby) if hobby && feed.respond_to?(:sections)

      items.each_with_index do |(item_title, days_ago), index|
        feed.feed_items.create!(
          title: item_title, guid: "demo-#{feed.id}-#{index}", url: "#{feed.site_url}/#{index}",
          published_at: (TODAY - days_ago).to_time.change(hour: 7 + index),
          read_at: days_ago > 3 ? (TODAY - days_ago + 1).to_time : nil,
          saved_at: index.zero? && days_ago < 3 ? 1.day.ago : nil,
          summary: "A demo item. The reader never fetched anything to produce this."
        )
      end
    end
  end

  # ------------------------------------------------------------------ travel

  # ------------------------------------------------------------------ photos

  # Real image files, because half of what the photo library and the world
  # map do is only visible when there is something to look at. They are
  # generated rather than shipped: an abstract band per place, so the grid
  # has colour and the map has pins without anyone's actual holiday being
  # committed to a public repository.
  #
  # Coordinates are the point. The map draws itself from these and from
  # nothing else — no tiles fetched, no place names looked up — which is
  # exactly the claim /about/features/world-map makes.
  PLACES = [
    # [ label, lat, long, hue, count, years-ago ]
    [ "Prentice Street", 40.9812, -81.3540, 30, 6, 0 ],
    [ "Millbrook Reserve", 40.9455, -81.4102, 110, 5, 0 ],
    [ "Spiddal, Galway", 53.2447, -9.3044, 190, 7, 3 ],
    [ "Cliffs of Moher", 52.9715, -9.4309, 205, 3, 3 ],
    [ "Chicago", 41.8781, -87.6298, 250, 3, 5 ],
    [ "Toronto", 43.6532, -79.3832, 280, 2, 8 ],
    [ "Sanibel Island", 26.4489, -82.0170, 45, 4, 9 ]
  ].freeze

  def build_photos(kay, danny, ify, people)
    travel = section("travel")
    albums = {}

    PLACES.each do |label, lat, long, hue, count, years_ago|
      count.times do |index|
        taken = (TODAY << (years_ago * 12 + index)) - (index * 3)
        photo = kay.photos.new(
          title: "#{label} #{index + 1}", taken_at: taken.to_time.change(hour: 10 + index),
          latitude: lat + (index * 0.004), longitude: long + (index * 0.006),
          ingest_status: "ready"
        )
        # Attached before the save: the image is validated as present, so
        # attaching afterwards fails the create it was meant to complete.
        photo.image.attach(
          io: StringIO.new(generated_image(hue + (index * 7))),
          filename: "#{label.parameterize}-#{index + 1}.jpg", content_type: "image/jpeg"
        )
        photo.save!
        tag(photo, travel) unless label.start_with?("Prentice")

        (albums[label] ||= []) << photo
      end
    end

    galway = kay.albums.create!(title: "Galway, 2023",
      description: "Two weeks at Colm's. The last summer Danny's dad knew everyone.")
    (albums["Spiddal, Galway"] + albums["Cliffs of Moher"]).each { |p| galway.album_photos.create!(photo: p) }
    galway.update!(cover_photo: albums["Spiddal, Galway"].first)

    reserve = kay.albums.create!(title: "Ify's first year birding",
      description: "Every Saturday since April, and the list to prove it.")
    albums["Millbrook Reserve"].each { |p| reserve.album_photos.create!(photo: p) }
    reserve.update!(cover_photo: albums["Millbrook Reserve"].first)

    home = kay.albums.create!(title: "Prentice Street",
      description: "The flat, the dog, and whatever was happening that week.")
    albums["Prentice Street"].each { |p| home.album_photos.create!(photo: p) }
    home.update!(cover_photo: albums["Prentice Street"].first)

    # Shared to the household, so the demo shows an album that isn't private.
    [ danny, ify ].each { |member| AccessGrant.create!(grantor: kay, grantee: member, subject: galway) }

    # Faces, on the photos where the app would know them.
    albums["Prentice Street"].first(3).each { |p| p.photo_people.create!(person: people[:ada]) }

    kay.share_links.create!(subject: galway, label: "For Colm and the kids",
      views_count: 31, last_viewed_at: 8.days.ago)

    @photos = albums
  end

  # A soft two-tone band. Not a photograph, and not pretending to be — it
  # reads as an image at thumbnail size, which is all the grid and the map
  # need, and it costs a few milliseconds instead of a licence.
  def generated_image(hue)
    require "vips"

    width, height = 800, 600
    top = Vips::Image.new_from_array([ [ 1 ] ]).cast(:uchar)
    base = top.embed(0, 0, width, height, extend: :copy)

    channels = [ hue % 360, 42, 78 ].each_with_index.map do |value, index|
      base.linear(0, colour_channel(hue, index, value)).cast(:uchar)
    end
    Vips::Image.bandjoin(channels).jpegsave_buffer(Q: 72, strip: true)
  end

  # Cheap HSV-ish spread: enough variety that a grid of them doesn't look
  # like one repeated tile.
  def colour_channel(hue, index, _value)
    angle = (hue + index * 120) * Math::PI / 180
    120 + (Math.sin(angle) * 70).round
  end

  def build_travel(kay, danny, ify)
    travel = section("travel")

    galway = kay.trips.create!(
      name: "Galway — Colm's", starts_on: Date.new(2023, 7, 8), ends_on: Date.new(2023, 7, 22),
      place_label: "County Galway, Ireland",
      north: 53.62, south: 53.14, east: -8.72, west: -9.34,
      description: "Two weeks at the family place. The last time Danny's dad was well enough to know everyone."
    )
    [ danny, ify ].each { |u| galway.memberships.create!(user: u) }
    galway.stays.create!(location: "Spiddal, Co. Galway", name: "The family house", kind: "friends_family",
      check_in: Date.new(2023, 7, 8), check_out: Date.new(2023, 7, 22), booking_status: "booked",
      latitude: 53.2447, longitude: -9.3044)

    obx = kay.trips.create!(
      name: "Outer Banks — October", starts_on: TODAY + 34, ends_on: TODAY + 41,
      place_label: "Outer Banks, North Carolina",
      description: "Booked in March when Danny still had the job. Paid for and non-refundable, so we are going, " \
                   "and honestly we need it."
    )
    [ danny, ify ].each { |u| obx.memberships.create!(user: u) }
    obx.stays.create!(location: "Kill Devil Hills, NC", name: "Sandpiper cottage", kind: "airbnb",
      check_in: TODAY + 34, check_out: TODAY + 41, booking_status: "booked",
      confirmation_code: "HMX4TQ92", cost_cents: 118_000, latitude: 36.0307, longitude: -75.6760,
      notes: "Paid in full in March. Dog-friendly — Biscuit is coming, Sable is going to Gabriel's.")
    obx.legs.create!(kind: "drive", origin: "Millbrook, OH", destination: "Kill Devil Hills, NC",
      starts_on: TODAY + 34, booking_status: "booked", notes: "Nine hours if we leave at five. We will not leave at five.")
    obx.legs.create!(kind: "drive", origin: "Kill Devil Hills, NC", destination: "Millbrook, OH",
      starts_on: TODAY + 41, booking_status: "booked")
    obx.comments.create!(user: danny, body: "Checked the cottage — it's paid, nothing owed. Only cost left is petrol and food.")
    obx.comments.create!(user: ify, body: "Bex says Pea Island is on the flyway in October. Can we do one morning?")

    canton = kay.trips.create!(
      name: "Mum's, Thanksgiving", starts_on: TODAY + 88, ends_on: TODAY + 91,
      place_label: "Millbrook, Ohio", description: "Ada's, as every year. Twelve people in a house built for four."
    )

    event(kay, "Leave for the Outer Banks", TODAY + 34, travel, all_day: true)
    task(kay, "Ask Gabriel about Sable for the OBX week", TODAY + 7, travel)
  end

  # ------------------------------------------------------------------- vault

  # The one part of the app a seed can only fill by knowing the password:
  # both containers are sealed with a key derived from it (D-vault-crypto,
  # D-diary-vault). That the demo has to unlock a keyring to write these —
  # rather than inserting rows like everything above — is the guarantee
  # working, so it is done properly rather than faked.
  def build_vault(kay, danny)
    kay_key = kay.keyring.unlock(PASSWORD)
    danny_key = danny.keyring.unlock(PASSWORD)

    credential(kay, "wifi", "Prentice Street wifi", username: "PrenticeSt_2G",
      secrets: { "password" => "roastedokra1997" }, vault_key: kay_key, share_with: danny)
    credential(kay, "login", "Mercy employee portal", username: "n.okafor",
      url: "https://example.org/mercy", secrets: { "password" => "Q7#tarragon-lattice" })
    credential(kay, "login", "Ohio Job & Family Services", username: "kokafor418",
      url: "https://example.org/odjfs", secrets: { "password" => "Bruce-friday-1981" }, vault_key: kay_key, share_with: danny)
    credential(kay, "card", "Capital One", username: "Nkechi Okafor",
      secrets: { "number" => "4111 1111 1111 1111", "expiry" => "09/28", "code" => "417" })
    credential(kay, "note", "Where everything is, if I'm not here",
      secrets: { "notes" => "Deeds and the lease: the grey box on top of the wardrobe. Mum's power of attorney: " \
                            "same box. Life insurance is through Mercy — HR has the policy number. " \
                            "The recovery kit for this vault is in the fire safe with the passports. " \
                            "Danny knows the safe code. Teresa has a spare key to Mum's." })
    credential(danny, "login", "Bellamy Mechanical careers", username: "dlynch78",
      url: "https://example.org/bellamy", secrets: { "password" => "Sheffler-june-22hrs" })

    diary(kay, kay_key, TODAY - 1, "Small mercies",
      "Danny got the second interview. He didn't tell me for four hours because he didn't want to jinx it, " \
      "and then he told me while doing the washing up with his back to me, which is how he tells me things " \
      "that matter.\n\nI have been holding my breath since July and I noticed tonight that I had stopped, " \
      "for about an hour.", "hopeful")
    diary(kay, kay_key, TODAY - 4, "Mum",
      "She asked me twice tonight whether I'd eaten. That's not new. What's new is that she asked from the " \
      "chair instead of getting up to check, and she'd have got up a year ago.\n\nI don't know how to say to " \
      "anyone that I am watching my mother get older in increments of about a foot and a half.", "heavy")
    diary(kay, kay_key, TODAY - 9, "Three months",
      "It has been three months since I messaged Marisol and her mother died in February. Every week I don't " \
      "do it makes the doing of it bigger. That is the entire mechanism and knowing it hasn't helped once.\n\n" \
      "Tomorrow. Before work, so I can't talk myself out of it over the day.", nil)
    diary(kay, kay_key, TODAY - 23, "The letter",
      "Two thousand one hundred and forty dollars for a fifteen-year-old's burst appendix, two years later, " \
      "from a company we have never heard of, in the same month Danny's cheque stopped.\n\n" \
      "Gabriel came up and sat at our table and told me exactly what to send. He didn't offer to help, he just " \
      "knew, and he told me. I don't think he knows what that was worth.", "angry")
    diary(danny, danny_key, TODAY - 6, nil,
      "Ify asked me to look at her bike and we ended up doing the whole drivetrain. Two hours in the garage, " \
      "her asking why about everything, me actually knowing the answers.\n\nBest afternoon since July. " \
      "Didn't think about the job once.", "good")
  end

  # Sharing a credential is two writes in lockstep — the visibility grant and
  # the item key re-wrapped to the grantee's public key — so it goes through
  # the same service the UI uses rather than inserting an AccessGrant that
  # would leave the grantee unable to decrypt what they can suddenly see.
  def credential(user, kind, name, secrets:, vault_key: nil, username: nil, url: nil, share_with: nil)
    record = user.credentials.create!(kind: kind, name: name, username: username, url: url)
    record.write_secrets!(secrets)
    Vault::Share.new(record, user, vault_key).grant([ share_with ]) if share_with
    record
  end

  def diary(user, vault_key, date, title, body, mood)
    setting, diary_key = DiarySetting.unlock_for(user, vault_key)
    entry = user.diary_entries.new(entry_date: date)
    entry.seal!({ "title" => title, "body" => body, "mood" => mood }.compact, diary_key: diary_key)
    setting
    entry
  end

  # ---------------------------------------------------------------- sharing

  # D9 made visible: a real household shares some things and not others, and
  # the demo should show a household that has actually thought about it.
  def build_sharing(kay, danny)
    [ section("money"), section("budget"), section("health") ].each do |s|
      AccessGrant.create!(grantor: kay, grantee: danny, subject: s)
    end
    AccessGrant.create!(grantor: danny, grantee: kay, subject: section("career"))
  end

  # ------------------------------------------------------------------ helpers

  def section(slug) = Section.find_by!(slug: slug)

  def tag(record, *sections)
    sections.compact.each { |s| record.section_taggings.create!(section: s) }
    record
  end

  def event(user, title, date, *sections, at: nil, all_day: false, location: nil,
            description: nil, care_kind: nil)
    starts = at ? Time.zone.parse("#{date} #{at}") : date.to_time
    record = user.events.create!(
      title: title, starts_at: starts, all_day: at.nil? || all_day,
      location: location, description: description, care_kind: care_kind
    )
    tag(record, *sections)
  end

  def task(user, title, due, *sections, bucket: :later, done: nil)
    record = user.tasks.create!(title: title, due_on: due, bucket: bucket,
      completed_at: done&.to_time)
    tag(record, *sections)
  end

  def goal(user, title, section, description, target, steps)
    record = user.goals.create!(title: title, description: description,
      target_on: target, broken_down_at: 1.week.ago)
    tag(record, section)

    steps.each do |step_title, due, done|
      task = user.tasks.create!(title: step_title, due_on: due, goal: record,
        completed_at: done&.to_time, bucket: due && due <= TODAY + 3 ? :today : :later)
      tag(task, section)
    end
    record
  end
end
