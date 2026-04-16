class MaintenanceMonitorJob < ApplicationJob
  queue_as :background

  # Scans HomeMaintenance records to find components that are past their standard intervals
  # and logs a maintenance warning via AgentLog when a threshold is hit.
  def perform
    HomeMaintenance.includes(:workspace).find_each do |maintenance|
      next unless maintenance.workspace

      next_service_date = maintenance.last_serviced_at + maintenance.standard_interval_days.days
      if Time.current > next_service_date
        days_overdue = (Time.current - next_service_date).to_i / 1.day
        metadata = {
          "home_maintenance_id" => maintenance.id,
          "key_component" => maintenance.key_component,
          "last_serviced_at" => maintenance.last_serviced_at.iso8601,
          "standard_interval_days" => maintenance.standard_interval_days,
          "days_overdue" => days_overdue
        }

        maintenance.workspace.agent_logs.create!(
          phase: "warning",
          content: "Maintenance Warning: #{maintenance.key_component} is overdue by #{days_overdue} day(s)",
          metadata_json: metadata,
          timestamp: Time.current
        )
      end
    end
  end
end
