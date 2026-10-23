# frozen_string_literal: true

require "spec_helper"
require_relative "../../billing_matrix/run"

RSpec.describe BillingMatrix::CLI do
  let(:rows) do
    %w[smoke/first interactions/first smoke/second smoke/third].map do |id|
      BillingMatrix::Row.new({"id" => id, "area" => id.split("/").first}, source: "example.yml")
    end
  end

  it "intersects repeated id filters with the area filter" do
    options = described_class.parse(%w[--id smoke/first --id interactions/first --area smoke])
    expect(described_class.new(options).send(:select, rows).map(&:id)).to eq(["smoke/first"])
  end

  %w[--id --area].each do |filter|
    it "rejects an unmatched #{filter} without writing results or booting the database" do
      options = described_class.parse([filter, "missing"])
      cli = described_class.new(options)
      allow(cli).to receive(:load_rows).and_return(rows)
      allow(BillingMatrix).to receive(:boot!)
      allow(BillingMatrix::Results).to receive(:new).and_call_original

      expect { expect(cli.call).to eq(described_class::EXIT_HARNESS_BROKEN) }
        .to output(/no rows matched/).to_stderr
      expect(BillingMatrix::Results).not_to have_received(:new)
      expect(BillingMatrix).not_to have_received(:boot!)
    end
  end

  it "rejects a shared shard database before boot cleanup" do
    cli = described_class.new(described_class.parse(%w[--shard 1/2]))
    allow(cli).to receive(:load_rows).and_return(rows)
    configuration = instance_double(ActiveRecord::DatabaseConfigurations::HashConfig, database: "shared_test")
    allow(ActiveRecord::Base).to receive(:connection_db_config).and_return(configuration)
    cleaner = DatabaseCleaner[:active_record]
    allow(cleaner).to receive(:clean_with)
    allow(FactoryBot).to receive(:reload)

    expect { expect(cli.call).to eq(described_class::EXIT_HARNESS_BROKEN) }
      .to output(/refusing to run shard 1\/2 against "shared_test"/).to_stderr
    expect(cleaner).not_to have_received(:clean_with)
    expect(FactoryBot).not_to have_received(:reload)
  end

  it "partitions selected rows without overlaps or omissions" do
    selected = (1..2).map do |index|
      options = described_class.parse(["--area", "smoke", "--shard", "#{index}/2"])
      described_class.new(options).send(:select, rows).map(&:id)
    end
    expect(selected).to eq([["smoke/first", "smoke/third"], ["smoke/second"]])
  end
end
