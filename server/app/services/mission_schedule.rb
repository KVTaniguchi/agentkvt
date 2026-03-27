class MissionSchedule
  WEEKDAYS = {
    "sunday" => 0,
    "monday" => 1,
    "tuesday" => 2,
    "wednesday" => 3,
    "thursday" => 4,
    "friday" => 5,
    "saturday" => 6
  }.freeze

  class << self
    def due?(mission, at: Time.current)
      scheduled_at = scheduled_window_start(mission.trigger_schedule, at: at)
      return false unless scheduled_at
      return false if at < scheduled_at

      mission.last_run_at.nil? || mission.last_run_at < scheduled_at
    end

    def scheduled_window_start(schedule, at: Time.current)
      kind, value = schedule.to_s.split("|", 2)
      case kind&.downcase
      when "daily"
        daily_start(value, at: at)
      when "weekly"
        weekly_start(value, at: at)
      else
        nil
      end
    end

    private

    def daily_start(value, at:)
      return nil if value.blank?

      hour_string, minute_string = value.split(":", 2)
      hour = parse_decimal_integer(hour_string)
      minute = parse_decimal_integer(minute_string)
      return nil unless hour && minute
      return nil unless (0..23).cover?(hour) && (0..59).cover?(minute)

      at.in_time_zone.change(hour:, min: minute, sec: 0)
    end

    def weekly_start(value, at:)
      return nil if value.blank?

      target_wday = WEEKDAYS[value.downcase]
      return nil unless target_wday

      current = at.in_time_zone.beginning_of_day
      days_until = target_wday - current.wday
      current + days_until.days
    end

    def parse_decimal_integer(value)
      Integer(value, 10, exception: false)
    end
  end
end
