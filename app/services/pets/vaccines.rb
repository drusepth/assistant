module Pets
  # The vaccine catalog (D-pet-vaccinations): per species, the vaccines the
  # professional bodies publish guidance for, so the log form is a checklist
  # rather than an empty box, two doses printed as "Rabies 3yr" and "Imrab 3"
  # are recognisably one vaccine, and the pet page can say which core vaccine
  # has no record at all.
  #
  # The Pets::CareKinds rule applies: **we only claim what we know.** Dogs,
  # cats, horses and rabbits get a list; birds, reptiles, fish and "other"
  # get none, their log form is free text, and nothing on their page claims a
  # vaccine is missing.
  #
  # What an entry deliberately does not carry:
  # - **A default duration.** `durations` are the lifetimes products are
  #   labelled for, offered as buttons; which one a dose has is on its
  #   certificate or in the owner's head. A guessed three years sends the
  #   reminder two years late, a guessed one year two years early.
  # - **Law.** Rabies rules differ by state and country, and the app does not
  #   know the household's.
  # - **A recommendation.** `core` repeats the published guidance, labelled
  #   as whose it is; whether Rex should get Lyme is the vet's call.
  #
  # `also_called` is display help for the checklist ("DHPP · DAPP · distemper
  # combo"). It is never matched against text — the model maps printed names
  # onto keys inside the closed set during intake (D-no-keyword-logic).
  #
  # Sources: AAHA 2022 Canine Vaccination Guidelines; AAHA/AAFP 2020 Feline
  # Vaccination Guidelines; AAEP Core and Risk-Based Vaccination Guidelines;
  # the RHDV2 and myxomatosis guidance from the house rabbit and veterinary
  # bodies (myxomatosis vaccine is not licensed everywhere — the US has none).
  module Vaccines
    Vaccine = Data.define(:key, :label, :also_called, :core, :durations, :about) do
      def core? = core == true
      def durations_phrase = durations.map { |months| Vaccines.duration_label(months) }.join(" or ")
    end

    GUIDANCE = {
      "dog" => "AAHA", "cat" => "AAHA/AAFP", "horse" => "AAEP", "rabbit" => "veterinary"
    }.freeze

    CATALOG = {
      "dog" => [
        Vaccine.new(key: "rabies", label: "Rabies", also_called: [], core: true, durations: [ 12, 36 ],
          about: "Required by law in many places; the certificate and tag number are what licensing and boarding ask for."),
        Vaccine.new(key: "dhpp", label: "DHPP", also_called: [ "DAPP", "DA2PP", "distemper combo" ], core: true, durations: [ 12, 36 ],
          about: "Distemper, adenovirus, parvovirus and parainfluenza in one shot."),
        Vaccine.new(key: "leptospirosis", label: "Leptospirosis", also_called: [ "Lepto" ], core: false, durations: [ 12 ],
          about: "For dogs around standing water, wildlife or livestock."),
        Vaccine.new(key: "bordetella", label: "Bordetella", also_called: [ "Kennel cough" ], core: false, durations: [ 6, 12 ],
          about: "Most boarding kennels, daycares and groomers require it."),
        Vaccine.new(key: "canine_influenza", label: "Canine influenza", also_called: [ "Dog flu", "H3N2/H3N8" ], core: false, durations: [ 12 ],
          about: "Often asked for alongside bordetella by kennels."),
        Vaccine.new(key: "lyme", label: "Lyme", also_called: [ "Borrelia" ], core: false, durations: [ 12 ],
          about: "For dogs in tick country.")
      ],
      "cat" => [
        Vaccine.new(key: "rabies", label: "Rabies", also_called: [], core: true, durations: [ 12, 36 ],
          about: "Required by law in many places, indoor cats included."),
        Vaccine.new(key: "fvrcp", label: "FVRCP", also_called: [ "Feline distemper combo" ], core: true, durations: [ 12, 36 ],
          about: "Rhinotracheitis, calicivirus and panleukopenia in one shot."),
        Vaccine.new(key: "felv", label: "FeLV", also_called: [ "Feline leukemia" ], core: false, durations: [ 12, 24 ],
          about: "Core for kittens; for adults it depends on whether they go outside or live with other cats."),
        Vaccine.new(key: "bordetella", label: "Bordetella", also_called: [], core: false, durations: [ 12 ],
          about: "Sometimes asked for by catteries and shelters."),
        Vaccine.new(key: "chlamydia", label: "Chlamydia", also_called: [ "Chlamydophila felis" ], core: false, durations: [ 12 ],
          about: "For cats in multi-cat households with a history of it.")
      ],
      "horse" => [
        Vaccine.new(key: "tetanus", label: "Tetanus", also_called: [], core: true, durations: [ 12 ], about: nil),
        Vaccine.new(key: "eee_wee", label: "EEE/WEE", also_called: [ "Eastern/Western equine encephalomyelitis" ], core: true, durations: [ 6, 12 ], about: nil),
        Vaccine.new(key: "west_nile", label: "West Nile", also_called: [], core: true, durations: [ 6, 12 ], about: nil),
        Vaccine.new(key: "rabies", label: "Rabies", also_called: [], core: true, durations: [ 12 ], about: nil),
        Vaccine.new(key: "equine_influenza", label: "Equine influenza", also_called: [ "Flu" ], core: false, durations: [ 6, 12 ],
          about: "Often required for shows, travel and boarding barns."),
        Vaccine.new(key: "ehv", label: "Rhinopneumonitis", also_called: [ "EHV-1/EHV-4", "Rhino" ], core: false, durations: [ 6, 12 ],
          about: "Pregnant mares are usually vaccinated on a tighter schedule."),
        Vaccine.new(key: "strangles", label: "Strangles", also_called: [ "Streptococcus equi" ], core: false, durations: [ 6, 12 ], about: nil),
        Vaccine.new(key: "potomac", label: "Potomac horse fever", also_called: [ "PHF" ], core: false, durations: [ 6, 12 ], about: nil),
        Vaccine.new(key: "botulism", label: "Botulism", also_called: [], core: false, durations: [ 12 ], about: nil)
      ],
      "rabbit" => [
        Vaccine.new(key: "rhdv2", label: "RHDV2", also_called: [ "Rabbit hemorrhagic disease" ], core: true, durations: [ 12 ],
          about: "Recommended wherever the virus has been reported."),
        Vaccine.new(key: "myxomatosis", label: "Myxomatosis", also_called: [], core: false, durations: [ 12 ],
          about: "Licensed in the UK and much of Europe, not in the US.")
      ]
    }.freeze

    # The lifetimes the form offers when no species list does: a free-text
    # vaccine still gets buttons, never a default.
    GENERIC_DURATIONS = [ 6, 12, 24, 36 ].freeze

    module_function

    def for(species) = CATALOG.fetch(species.to_s, [])
    def known?(species) = CATALOG.key?(species.to_s)
    def find(species, key) = self.for(species).find { |vaccine| vaccine.key == key.to_s }
    def core(species) = self.for(species).select(&:core?)

    # Whose guidance "core" means for this species, for copy: "AAHA lists…".
    def guidance(species) = GUIDANCE[species.to_s]

    # Every key any species has, for the intake field's closed set — the pet a
    # landing names isn't known until it resolves, so the kind validates the
    # key against *her* species at write time.
    def all_keys = CATALOG.values.flatten.map(&:key).uniq

    def label_for(key) = CATALOG.values.flatten.find { |vaccine| vaccine.key == key.to_s }&.label

    def durations_for(species, key)
      find(species, key)&.durations.presence || GENERIC_DURATIONS
    end

    def duration_label(months)
      return "#{months} months" if months < 12 || months % 12 != 0

      years = months / 12
      years == 1 ? "1 year" : "#{years} years"
    end
  end
end
