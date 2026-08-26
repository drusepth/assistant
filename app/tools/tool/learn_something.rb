module Tool
  # The enrollment door (docs/EDUCATION_PLAN.md §6). What began as goal
  # capture with framing now lands the whole spine: a Subject with its own
  # curriculum tree (from the commons shelf when the topic names a course,
  # generated otherwise — D-curriculum-commons), plus the same paced
  # Goal→Tasks plan as before, aimed at the first topic so Today keeps
  # pulling the learner back (D-education-spine).
  class LearnSomething < Base
    self.title = "Learn something"
    self.description = "Name a topic — get your own curriculum and a paced plan of day-sized first steps."
    self.section_slugs = %w[ education ]
    self.kind = :plan

    input :topic, required: true, label: "What do you want to learn?"
    input :angle,
      label: "Your level, goal, or deadline",
      hint: "Optional — “complete beginner”, “conversational by June”, “for a career switch”."

    BRIEF = <<~BRIEF.freeze
      This goal is a personal study plan. Structure the steps as a progression:
      start from orientation and fundamentals, alternate learning with hands-on
      practice, and end with a step where the learner produces or does something
      that proves it stuck. Each step names concrete material or an exercise —
      never "study more" or "keep practicing".
    BRIEF

    def call
      subject = find_or_create_subject
      goal = plan_goal!(title: goal_title, brief: BRIEF, description: inputs[:angle].presence)
      first_topic = subject.current_topic
      first_topic.update!(goal: goal) if first_topic && first_topic.goal.nil?
      subject
    end

    private
      def find_or_create_subject
        course = Curriculum::Commons.match(inputs[:topic])
        subject =
          if course && (enrolled = user.subjects.find_by(commons_key: course.key))
            enrolled
          elsif course
            Curriculum::Commons.instantiate!(course.key, user: user, interest_frame: inputs[:angle].presence).tap do |enrolled|
              PersonalizeSubjectJob.perform_later(enrolled) if enrolled.interest_frame.present?
            end
          else
            generated_subject
          end
        subject.sections = (subject.sections.to_a + self.class.section_records).uniq
        record(subject) unless run.items.include?(subject)
        subject
      end

      def generated_subject
        subject = user.subjects.create!(
          title: inputs[:topic].to_s.strip,
          interest_frame: inputs[:angle].presence
        )
        begin
          Education::GenerateTree.new(subject: subject, profile: profile).build!
        ensure
          # Stamp even on failure (the Goal pattern): a failed generation
          # leaves an empty syllabus the learner can retry from its page.
          subject.update_column(:tree_built_at, Time.current)
        end
        subject
      end

      def goal_title = "Learn #{inputs[:topic].to_s.strip}"
  end
end
