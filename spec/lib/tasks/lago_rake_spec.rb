# frozen_string_literal: true

require "rails_helper"

require "rake"

RSpec.describe "lago:support_info" do # rubocop:disable RSpec/DescribeClass
  let(:task) { Rake::Task["lago:support_info"] }

  let(:report) do
    original = $stdout
    captured = StringIO.new
    $stdout = captured
    begin
      task.invoke
    ensure
      $stdout = original
    end
    captured.string
  end

  before do
    Rake.application.rake_require("tasks/lago")
    Rake::Task.define_task(:environment)
    task.reenable
    allow(Clickhouse::BaseRecord).to receive(:connection)
      .and_raise(StandardError, "clickhouse unavailable in specs")
    allow(Clickhouse::BaseRecord).to receive(:connection_pool)
      .and_raise(StandardError, "clickhouse unavailable in specs")
  end

  it_behaves_like "a lago support diagnostic report"
end
