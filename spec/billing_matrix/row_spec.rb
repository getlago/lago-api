# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require_relative "../../billing_matrix/runner/row"

RSpec.describe BillingMatrix::Row do
  let(:document) do
    {"id" => "smoke/example", "area" => "smoke", "expect" => {"invoices" => 0},
     "timeline" => [{"at" => "2026-03-01T00:00:00Z", "do" => "perform_billing"}]}
  end

  def validate(document)
    described_class.new(document, source: "example.yml").validate!
  end

  it "accepts a supported row" do
    expect(validate(document).id).to eq("smoke/example")
  end

  describe ".load_all" do
    let(:directory) { Dir.mktmpdir("matrix-rows") }
    let(:first_path) { File.join(directory, "first.yml") }
    let(:second_directory) { File.join(directory, "controls") }
    let(:second_path) { File.join(second_directory, "second.yml") }

    before do
      FileUtils.mkdir_p(second_directory)
      File.write(first_path, YAML.dump([document.merge("control" => "smoke/control")]))
      File.write(second_path, YAML.dump([document.merge("id" => "smoke/control")]))
    end

    after { FileUtils.remove_entry(directory) }

    it "loads an individual file" do
      expect(described_class.load_all(second_path).map(&:id)).to eq(["smoke/control"])
    end

    it "resolves controls across combined file and directory inputs" do
      expect(described_class.load_all([first_path, second_directory]).map(&:id)).to eq(%w[smoke/example smoke/control])
    end

    it "rejects duplicate ids across combined paths" do
      expect { described_class.load_all([directory, second_path]) }
        .to raise_error(BillingMatrix::InvalidRow, /duplicates row "smoke\/control"/)
    end

    it "rejects controls absent from all inputs" do
      expect { described_class.load_all(first_path) }
        .to raise_error(BillingMatrix::InvalidRow, /not a loaded row/)
    end
  end

  it "rejects unsupported verbs" do
    document["timeline"].first["do"] = "unknown"
    expect { validate(document) }.to raise_error(BillingMatrix::InvalidRow, /unknown verb/)
  end

  it "rejects backwards time" do
    document["timeline"] << {"at" => "2026-02-01T00:00:00Z", "do" => "perform_billing"}
    expect { validate(document) }.to raise_error(BillingMatrix::InvalidRow, /earlier than/)
  end

  it "requires arithmetic for nonzero amounts" do
    document["expect"] = {"invoice" => {"total_amount_cents" => 100}}
    expect { validate(document) }.to raise_error(BillingMatrix::InvalidRow, /math.*is required/)
  end

  it "rejects a single event without an explicit opt-in" do
    document["timeline"] = [{"at" => "2026-03-01T00:00:00Z", "do" => "ingest_events", "events" => [{}]}]
    expect { validate(document) }.to raise_error(BillingMatrix::InvalidRow, /exactly one ingest_events/)
  end

  it "rejects duplicate ids across files" do
    row = validate(document)
    expect { described_class.reject_duplicate_ids!([row, row]) }.to raise_error(BillingMatrix::InvalidRow, /duplicates row/)
  end

  it "rejects a missing control row" do
    row = validate(document.merge("control" => "smoke/missing"))
    expect { described_class.check_controls!([row]) }.to raise_error(BillingMatrix::InvalidRow, /not a loaded row/)
  end
end
