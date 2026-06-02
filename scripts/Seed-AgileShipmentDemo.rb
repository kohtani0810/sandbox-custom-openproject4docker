# frozen_string_literal: true

# Run from the repository root in WSL:
# docker compose cp scripts/Seed-AgileShipmentDemo.rb openproject:/tmp/Seed-AgileShipmentDemo.rb
# docker compose exec -T openproject env RAILS_ENV=production \
#   bundle exec rails runner /tmp/Seed-AgileShipmentDemo.rb

project_identifier = "shipment-status-agile-demo"
temporary_password = "DemoChange!2026"

users = [
  ["demo-pj-lead", "佐藤", "リーダー", "demo-pj-lead@example.invalid"],
  ["demo-member-a", "田中", "メンバーA", "demo-member-a@example.invalid"],
  ["demo-member-b", "鈴木", "メンバーB", "demo-member-b@example.invalid"],
  ["demo-member-c", "高橋", "メンバーC", "demo-member-c@example.invalid"]
].to_h do |login, firstname, lastname, mail|
  user = User.find_or_initialize_by(login: login)
  if user.new_record?
    user.assign_attributes(
      firstname: firstname,
      lastname: lastname,
      mail: mail,
      password: temporary_password,
      password_confirmation: temporary_password,
      status: "active",
      force_password_change: true
    )
    user.save!
  end
  [login, user]
end

project = Project.find_or_initialize_by(identifier: project_identifier)
project.name = "出庫状況管理機能開発（アジャイルサンプル）"
project.description = <<~TEXT
  出庫状況照会機能と出庫状況登録機能を開発する模擬プロジェクト。
  PJリーダー1名、メンバー3名で、2週間単位のスプリントを基本として進める。
TEXT
project.public = false
project.workspace_type = "project"
project.enabled_module_names = %w[
  backlogs
  board_view
  costs
  documents
  gantt
  meetings
  news
  wiki
  work_package_tracking
]
project.save!

project.types = Type.where(name: ["タスク", "マイルストーン", "機能", "エピック", "ユーザストーリー", "不具合"])

roles = {
  lead: Role.find_by(name: "リーダー") || Role.find_by(name: "プロジェクト管理者"),
  member: Role.find_by(name: "メンバー")
}
raise "Required roles are missing" unless roles.values.all?

users.each do |login, user|
  member = Member.find_or_initialize_by(project: project, principal: user)
  member.roles = [login == "demo-pj-lead" ? roles[:lead] : roles[:member]]
  member.save!
end

versions = [
  ["Sprint 0: 準備", "2026-06-03", "2026-06-05"],
  ["Sprint 1: 出庫状況照会", "2026-06-08", "2026-06-19"],
  ["Sprint 2: 出庫状況登録", "2026-06-22", "2026-07-03"],
  ["Sprint 3: 結合試験・リリース", "2026-07-06", "2026-07-10"]
].to_h do |name, start_date, due_date|
  version = Version.find_or_initialize_by(project: project, name: name)
  version.assign_attributes(
    description: "#{name} の模擬スプリント",
    start_date: Date.parse(start_date),
    effective_date: Date.parse(due_date),
    status: "open",
    sharing: "none"
  )
  version.save!
  [name, version]
end

author = User.find_by(login: "admin") || users.fetch("demo-pj-lead")
status = Status.find_by(name: "新しく作成") || Status.first
raise "A work package status is required" unless status

types = Type.where(name: ["タスク", "マイルストーン", "機能", "エピック", "ユーザストーリー"]).index_by(&:name)
raise "Required work package types are missing" unless %w[タスク マイルストーン 機能 エピック ユーザストーリー].all? { |name| types[name] }

def upsert_work_package(project:, author:, status:, priority:, types:, versions:, users:, subject:, type:, start_date:, due_date:, hours: nil, assignee: nil, sprint: nil, parent: nil, description: nil)
  work_package = WorkPackage.find_or_initialize_by(project: project, subject: subject)
  work_package.assign_attributes(
    author: author,
    status: status,
    priority: priority,
    type: types.fetch(type),
    start_date: Date.parse(start_date),
    due_date: Date.parse(due_date),
    estimated_hours: hours,
    assigned_to: assignee ? users.fetch(assignee) : nil,
    version: sprint ? versions.fetch(sprint) : nil,
    parent: parent,
    description: description || "#{subject} の模擬チケット"
  )
  work_package.save!
  work_package
end

common = {
  project: project,
  author: author,
  status: status,
  priority: IssuePriority.default || IssuePriority.first,
  types: types,
  versions: versions,
  users: users
}

epic = upsert_work_package(**common,
  subject: "出庫状況管理機能開発",
  type: "エピック",
  start_date: "2026-06-03",
  due_date: "2026-07-10",
  assignee: "demo-pj-lead")

inquiry = upsert_work_package(**common,
  subject: "出庫状況照会機能",
  type: "機能",
  start_date: "2026-06-08",
  due_date: "2026-06-19",
  assignee: "demo-member-a",
  parent: epic)

registration = upsert_work_package(**common,
  subject: "出庫状況登録機能",
  type: "機能",
  start_date: "2026-06-22",
  due_date: "2026-07-03",
  assignee: "demo-member-b",
  parent: epic)

tasks = [
  ["キックオフ・完了条件の合意", "タスク", "2026-06-03", "2026-06-03", 3, "demo-pj-lead", "Sprint 0: 準備", epic],
  ["ユーザーストーリー整理", "ユーザストーリー", "2026-06-03", "2026-06-04", 6, "demo-pj-lead", "Sprint 0: 準備", epic],
  ["出庫データ項目・状態遷移の整理", "タスク", "2026-06-04", "2026-06-05", 8, "demo-member-c", "Sprint 0: 準備", epic],
  ["API・DB設計レビュー", "タスク", "2026-06-05", "2026-06-05", 4, "demo-pj-lead", "Sprint 0: 準備", epic],

  ["照会条件・一覧項目の確定", "ユーザストーリー", "2026-06-08", "2026-06-09", 6, "demo-pj-lead", "Sprint 1: 出庫状況照会", inquiry],
  ["出庫状況照会API実装", "タスク", "2026-06-09", "2026-06-12", 20, "demo-member-a", "Sprint 1: 出庫状況照会", inquiry],
  ["出庫状況照会画面実装", "タスク", "2026-06-10", "2026-06-15", 24, "demo-member-b", "Sprint 1: 出庫状況照会", inquiry],
  ["照会条件バリデーション実装", "タスク", "2026-06-12", "2026-06-15", 10, "demo-member-c", "Sprint 1: 出庫状況照会", inquiry],
  ["照会機能単体テスト", "タスク", "2026-06-16", "2026-06-18", 16, "demo-member-a", "Sprint 1: 出庫状況照会", inquiry],
  ["照会機能レビュー・デモ", "タスク", "2026-06-19", "2026-06-19", 4, "demo-pj-lead", "Sprint 1: 出庫状況照会", inquiry],

  ["登録項目・入力ルールの確定", "ユーザストーリー", "2026-06-22", "2026-06-23", 6, "demo-pj-lead", "Sprint 2: 出庫状況登録", registration],
  ["出庫状況登録API実装", "タスク", "2026-06-23", "2026-06-26", 20, "demo-member-b", "Sprint 2: 出庫状況登録", registration],
  ["出庫状況登録画面実装", "タスク", "2026-06-23", "2026-06-29", 28, "demo-member-a", "Sprint 2: 出庫状況登録", registration],
  ["登録時バリデーション・排他制御", "タスク", "2026-06-25", "2026-06-30", 20, "demo-member-c", "Sprint 2: 出庫状況登録", registration],
  ["登録機能単体テスト", "タスク", "2026-07-01", "2026-07-02", 16, "demo-member-b", "Sprint 2: 出庫状況登録", registration],
  ["登録機能レビュー・デモ", "タスク", "2026-07-03", "2026-07-03", 4, "demo-pj-lead", "Sprint 2: 出庫状況登録", registration],

  ["結合テスト仕様作成", "タスク", "2026-07-06", "2026-07-06", 6, "demo-member-c", "Sprint 3: 結合試験・リリース", epic],
  ["照会・登録機能の結合テスト", "タスク", "2026-07-07", "2026-07-08", 16, "demo-member-a", "Sprint 3: 結合試験・リリース", epic],
  ["受入確認・修正", "タスク", "2026-07-09", "2026-07-09", 16, "demo-member-b", "Sprint 3: 結合試験・リリース", epic],
  ["リリース判定", "マイルストーン", "2026-07-10", "2026-07-10", 2, "demo-pj-lead", "Sprint 3: 結合試験・リリース", epic]
]

tasks.each do |subject, type, start_date, due_date, hours, assignee, sprint, parent|
  upsert_work_package(**common,
    subject: subject,
    type: type,
    start_date: start_date,
    due_date: due_date,
    hours: hours,
    assignee: assignee,
    sprint: sprint,
    parent: parent)
end

puts "PROJECT=#{project.identifier}"
puts "PROJECT_ID=#{project.id}"
puts "USERS=#{users.keys.join(',')}"
puts "VERSIONS=#{versions.size}"
puts "WORK_PACKAGES=#{project.work_packages.count}"
puts "TEMPORARY_PASSWORD=#{temporary_password}"
