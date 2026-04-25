module ObjectiveComposerTemplates
  TEMPLATE_KEYS = %w[
    generic
    budget
    date_night
    trip_planning
    household_planning
    shopping
    restaurant_reservation
  ].freeze

  FIELD_KEYS = %w[
    context
    success_criteria
    constraints
    preferences
    deliverable
    open_questions
  ].freeze

  TEMPLATE_TITLES = {
    "generic" => "Custom Objective",
    "budget" => "Budget",
    "date_night" => "Date Night",
    "trip_planning" => "Trip Planning",
    "household_planning" => "Household Planning",
    "shopping" => "Shopping",
    "restaurant_reservation" => "Restaurant Reservation"
  }.freeze

  TEMPLATE_GUIDANCE = {
    "generic" => "Clarify the desired outcome, the context, major constraints, and what a useful final result should look like.",
    "budget" => "Clarify the time horizon, target savings or spending outcome, important categories, hard limits, and the budget format the user wants back.",
    "date_night" => "Clarify the occasion, timing, budget, location, preferences, and the kind of plan or recommendations the user wants back.",
    "trip_planning" => "Clarify the destination, timing, travelers, budget, logistics constraints, and the itinerary or comparison deliverable the user wants.",
    "household_planning" => "Clarify the household project, deadline, budget, constraints, participants, and the checklist or plan the user wants.",
    "shopping" => "Clarify the items needed, the preferred retailers (e.g. Target), any price thresholds, delivery/pickup preferences, and the final deliverable (e.g. cart ready for checkout).",
    "restaurant_reservation" => "Clarify the party size, date and time, neighborhood or city, cuisine or vibe preference, budget per person, and whether to just surface options or actually make the booking."
  }.freeze

  REQUIRED_FIELDS = {
    "generic" => %w[context success_criteria deliverable],
    "budget" => %w[context constraints success_criteria deliverable],
    "date_night" => %w[context constraints preferences success_criteria],
    "trip_planning" => %w[context constraints preferences success_criteria deliverable],
    "household_planning" => %w[context constraints success_criteria deliverable],
    "shopping" => %w[context constraints preferences success_criteria deliverable],
    "restaurant_reservation" => %w[context constraints preferences success_criteria]
  }.freeze

  def self.normalize_template_key(value)
    key = value.to_s.strip
    TEMPLATE_KEYS.include?(key) ? key : "generic"
  end

  def self.guidance_for(value)
    TEMPLATE_GUIDANCE.fetch(normalize_template_key(value))
  end

  def self.title_for(value)
    TEMPLATE_TITLES.fetch(normalize_template_key(value))
  end

  def self.required_fields_for(value)
    REQUIRED_FIELDS.fetch(normalize_template_key(value))
  end
end
