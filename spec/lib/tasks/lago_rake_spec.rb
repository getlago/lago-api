# frozen_string_literal: true

require "rails_helper"

require "rake"

RSpec.describe "lago:support_info" do # rubocop:disable RSpec/DescribeClass
  let(:task) { Rake::Task["lago:support_info"] }

  before do
    Rake.application.rake_require("tasks/lago")
    Rake::Task.define_task(:environment)
    task.reenable
    stub_request(:post, %r{clickhouse}).to_return(status: 500)
  end

  it "prints the support diagnostic report" do
    expect { task.invoke }
      .to output(/LAGO SUPPORT DIAGNOSTIC.*END OF DIAGNOSTIC/m).to_stdout
  end
end
