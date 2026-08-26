module Pets
  # A pet's care-radar kinds (D-pet-care-radar). A wellness exam is a checkup
  # with a different noun, so these are ordinary Health::CareRadar::Kind rows
  # and everything downstream — classification, the four states, the tiles —
  # is the machinery that was already there.
  #
  # **We only claim what we know.** Dogs and cats get a real slate; a rabbit,
  # bird, reptile, fish or horse gets one generic wellness kind and nothing
  # more, because we do not know an iguana's cadence and inventing one is the
  # invented-cardiologist failure in a smaller costume. The radar's "not
  # tracked" state is an honest answer, and per-pet custom kinds are the rung
  # for the owner who does know (deferred with the rest of the tuning).
  module CareKinds
    Kind = Health::CareRadar::Kind

    module_function

    def for(pet)
      case pet.species
      when "dog" then dog(pet)
      when "cat" then cat(pet)
      else [ wellness(pet) ]
      end
    end

    def dog(pet)
      [ wellness(pet), vaccinations(pet), dental(pet), parasite(pet), grooming(pet), nails(pet) ]
    end

    def cat(pet)
      [ wellness(pet), vaccinations(pet), dental(pet), parasite(pet) ]
    end

    # Titles carry the pet's name because the event capture they seed lands on
    # a shared calendar: "Wellness exam" on a household calendar with two dogs
    # is a question, and "Rex — wellness exam" is an answer.
    def wellness(pet)
      Kind.new(
        key: "pet_wellness", label: "Wellness exam", provider: "veterinarian",
        appointment_title: "#{pet.name} — wellness exam", book_title: "Book #{pet.name} a wellness exam",
        interval: 12.months, generic: true,
        patterns: [ /wellness/, /annual (exam|visit|check)/, /check[ -]?up/, /\bvet\b/, /veterinar/, /physical/ ]
      )
    end

    def vaccinations(pet)
      Kind.new(
        key: "pet_vaccinations", label: "Vaccinations", provider: "veterinarian",
        appointment_title: "#{pet.name} — vaccinations", book_title: "Book #{pet.name}'s vaccinations",
        interval: 12.months,
        patterns: [ /vaccin/, /\bshots?\b/, /booster/, /rabies/, /\bjab\b/ ]
      )
    end

    def dental(pet)
      Kind.new(
        key: "pet_dental", label: "Dental", provider: "veterinarian",
        appointment_title: "#{pet.name} — dental", book_title: "Book #{pet.name} a dental",
        interval: 12.months,
        patterns: [ /dent/, /\bteeth\b/, /\btooth\b/, /scale and polish/ ]
      )
    end

    # The monthly cadence HEALTH.md §3 was waiting for: a preventative given
    # on the first of the month doesn't round to anything sensible in whole
    # months, which is what made intervals durations.
    def parasite(pet)
      Kind.new(
        key: "pet_parasite", label: "Parasite prevention", provider: "veterinarian",
        appointment_title: "#{pet.name} — flea and worm treatment", book_title: "#{pet.name} is due a flea and worm treatment",
        interval: 1.month,
        patterns: [ /flea/, /\btick\b/, /worm/, /parasite/, /heartworm/, /spot[- ]?on/, /preventative/ ]
      )
    end

    # Upkeep, not care — the haircut rule (D-nonclinical-care-kinds) applied
    # to the animal that actually needs one every six weeks. No find-a-vet, no
    # visit prep, and the copy says "groom" rather than "visit".
    def grooming(pet)
      Kind.new(
        key: "pet_grooming", label: "Grooming", provider: "groomer",
        appointment_title: "#{pet.name} — grooming", book_title: "Book #{pet.name} a groom",
        interval: 6.weeks, clinical: false,
        patterns: [ /groom/, /\bclip(ped|ping)?\b/, /\bbath\b/, /\bstrip(ped|ping)?\b/ ]
      )
    end

    def nails(pet)
      Kind.new(
        key: "pet_nails", label: "Nail trim", provider: "groomer",
        appointment_title: "#{pet.name} — nail trim", book_title: "#{pet.name} is due a nail trim",
        interval: 6.weeks, clinical: false,
        patterns: [ /nail/, /\bclaws?\b/ ]
      )
    end
  end
end
