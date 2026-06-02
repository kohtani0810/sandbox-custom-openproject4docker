# frozen_string_literal: true

project = Project.find_by!(identifier: "shipment-status-agile-demo")
author = User.find_by(login: "admin") || User.find_by!(login: "demo-pj-lead")
assignee = User.find_by!(login: "demo-member-c")
status = Status.find_by(name: "新しく作成") || Status.first
priority = IssuePriority.default || IssuePriority.first
task_type = Type.find_by!(name: "タスク")
epic = project.work_packages.find_by!(subject: "出庫状況管理機能開発")
sprint = project.versions.find_by!(name: "Sprint 3: 結合試験・リリース")

changed = project.work_packages.find_by!(subject: "出庫状況照会画面実装")
changed.update!(estimated_hours: 32)

rescheduled = project.work_packages.find_by!(subject: "照会条件バリデーション実装")
rescheduled.update!(
  schedule_manually: true,
  due_date: Date.parse("2026-06-17")
)

removed = project.work_packages.find_by(subject: "API・DB設計レビュー")
removed&.destroy!

added = WorkPackage.find_or_initialize_by(
  project: project,
  subject: "出庫状況CSVダウンロード追加対応"
)
added.assign_attributes(
  author: author,
  assigned_to: assignee,
  status: status,
  priority: priority,
  type: task_type,
  parent: epic,
  version: sprint,
  start_date: Date.parse("2026-07-07"),
  due_date: Date.parse("2026-07-08"),
  estimated_hours: 12,
  description: "ベースライン比較画面で追加タスクを確認するための模擬変更"
)
added.save!

puts "CHANGED=#{changed.id}|#{changed.subject}|estimated_hours=#{changed.estimated_hours}"
puts "RESCHEDULED=#{rescheduled.id}|#{rescheduled.subject}|due_date=#{rescheduled.due_date}"
puts "REMOVED=#{removed&.id}|API・DB設計レビュー"
puts "ADDED=#{added.id}|#{added.subject}|estimated_hours=#{added.estimated_hours}"
