# frozen_string_literal: true

require "fileutils"
require "json"

action = ARGV.fetch(0, "refresh")
project_identifier = ARGV.fetch(1, "shipment-status-agile-demo")
label = ARGV[2] || Time.now.strftime("%Y-%m-%d %H:%M")
note = ARGV[3] || ""
project = Project.find_by!(identifier: project_identifier)
output_dir = File.join("/app/tmp/pj-baselines", project_identifier)
FileUtils.mkdir_p(output_dir)

work_packages = project.work_packages.reorder(nil).includes(:type, :status, :assigned_to).map do |wp|
  {
    id: wp.id,
    subject: wp.subject,
    type: wp.type&.name,
    status: wp.status&.name,
    assignee: wp.assigned_to&.name,
    start_date: wp.start_date&.iso8601,
    due_date: wp.due_date&.iso8601,
    estimated_hours: wp.estimated_hours&.to_f,
    parent_id: wp.parent_id
  }
end.sort_by { |wp| wp[:id] }

payload = {
  project_identifier: project.identifier,
  project_name: project.name,
  captured_at: Time.now.iso8601,
  total_estimated_hours: work_packages.sum { |wp| wp[:estimated_hours].to_f },
  work_packages: work_packages
}

File.write(File.join(output_dir, "current.json"), JSON.pretty_generate(payload))

if action == "snapshot"
  timestamp = Time.now.utc.strftime("%Y%m%dT%H%M%SZ")
  filename = "baseline-#{timestamp}.json"
  File.write(File.join(output_dir, filename), JSON.pretty_generate(payload))

  index_file = File.join(output_dir, "index.json")
  index = File.exist?(index_file) ? JSON.parse(File.read(index_file)) : {
    "project_identifier" => project.identifier,
    "project_name" => project.name,
    "baselines" => []
  }
  index["baselines"].unshift({
    "file" => filename,
    "label" => label,
    "note" => note,
    "captured_at" => payload[:captured_at]
  })
  File.write(index_file, JSON.pretty_generate(index))
  puts "SNAPSHOT=#{filename}"
elsif action == "refresh"
  puts "REFRESHED=current.json"
else
  raise "Unknown action: #{action}. Use snapshot or refresh."
end

puts "PROJECT=#{project.identifier}"
puts "WORK_PACKAGES=#{work_packages.length}"
puts "TOTAL_ESTIMATED_HOURS=#{payload[:total_estimated_hours]}"
