# Health-section constants shared by the controller and views.
module Health
  # Tools the Health page's lead panels already surface with better
  # context (prefilled, next to the data they read); the Act zone hides
  # them so nine undifferentiated cards become four scannable ones.
  PANEL_TOOL_SLUGS = %w[ find_care insurance_explainer compare_plans check_in start_a_practice ].freeze
end
