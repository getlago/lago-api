# frozen_string_literal: true

require "rails_helper"

require "rake"

RSpec.describe "lago:support_info" do # rubocop:disable RSpec/DescribeClass
  let(:task) { Rake::Task["lago:support_info"] }

  before do
    Rake.application.rake_require("tasks/lago")
    Rake::Task.define_task(:environment)
    task.reenable
    allow(Clickhouse::BaseRecord).to receive(:connection)
      .and_raise(StandardError, "clickhouse unavailable in specs")
  end

  it "prints the support diagnostic report" do
    expect { task.invoke }
      .to output(/LAGO SUPPORT DIAGNOSTIC.*END OF DIAGNOSTIC/m).to_stdout
  end
end
