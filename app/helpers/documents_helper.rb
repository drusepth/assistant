module DocumentsHelper
  def document_auto_sort_hint
    if auto_sort_enabled?
      "Your assistant reads it, summarizes it in plain language, and files it into sections."
    else
      "Configure an AI model in Settings to get summaries; a description and sections can be added after saving."
    end
  end
end
