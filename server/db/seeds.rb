workspace = Workspace.find_or_create_by!(slug: ENV.fetch("DEFAULT_WORKSPACE_SLUG", "default")) do |record|
  record.name = ENV.fetch("DEFAULT_WORKSPACE_NAME", "Default Workspace")
  record.server_mode = "single_mac_brain"
end

puts "Seeded workspace #{workspace.slug} (#{workspace.id})"
