# `documents.health_plan` held two people's answers in one column: the
# owner's pin, and — since D-document-intake — the reader's verdict, written
# there whenever the owner hadn't answered. The document page couldn't tell
# them apart, so a vet sheet the reader called "not insurance" showed a
# select reading "No — keep it off" as if its owner had banished it, and a
# re-analysis could never change the reader's mind because the column
# already had a value.
#
# From here the column is the owner's word only, and the reader's verdict is
# a fact filed with the rest of what the analysis found
# (`extracted_facts["health_plan"]`), replaced on every re-read. This moves
# the verdicts already written. A value on an analyzed document is almost
# always the reader's (the job filled every unanswered one), so all of them
# move: every document still counts or doesn't exactly as before, and the
# rare owner pin on an already-read document becomes the reader's answer —
# which it agreed with or the owner would have had to overrule a select
# that showed the reader's answer as their own.
class MoveReaderHealthPlanVerdictToFacts < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL.squish
      UPDATE documents
      SET extracted_facts = json_set(COALESCE(extracted_facts, '{}'), '$.health_plan',
                                     CASE health_plan WHEN 1 THEN json('true') ELSE json('false') END),
          health_plan = NULL
      WHERE analysis_status = 'analyzed' AND health_plan IS NOT NULL
    SQL
  end

  def down
    execute <<~SQL.squish
      UPDATE documents
      SET health_plan = CASE json_extract(extracted_facts, '$.health_plan') WHEN 1 THEN 1 ELSE 0 END,
          extracted_facts = json_remove(extracted_facts, '$.health_plan')
      WHERE health_plan IS NULL AND json_type(extracted_facts, '$.health_plan') IN ('true', 'false')
    SQL
  end
end
