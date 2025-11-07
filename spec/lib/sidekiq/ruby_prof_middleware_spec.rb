# frozen_string_literal: true

require "rails_helper"

RSpec.describe Sidekiq::RubyProfMiddleware do
  subject(:middleware) { described_class.new(**options) }

  let(:test_dir) { "tmp/test_ruby_prof_#{SecureRandom.hex(4)}" }
  let(:options) { {dir: test_dir} }
  let(:instance) { nil }
  let(:queue) { "default" }
  let(:job_hash) do
    {
      "class" => "TestJob",
      "jid" => "test_jid_123",
      "enqueued_at" => Time.current.to_f
    }
  end

  # Test method that will be profiled
  def test_method_to_profile
    "result_from_test_method"
  end

  def heavy_work
    value = 0
    200_000.times { value += 1 }
    value
  end

  def light_work
    rand
  end

  after do
    FileUtils.rm_rf(test_dir) if Dir.exist?(test_dir)
  end

  describe "#call" do
    let(:block) { -> { test_method_to_profile } }

    it "returns the block result" do
      result = middleware.call(instance, job_hash, queue, &block)

      expect(result).to eq("result_from_test_method")
    end

    it "creates job directory" do
      middleware.call(instance, job_hash, queue, &block)

      expect(Dir.exist?("#{test_dir}/TestJob")).to be(true)
    end

    it "generates profile files" do
      middleware.call(instance, job_hash, queue, &block)

      profile_dir = "#{test_dir}/TestJob"

      expect(Dir.exist?(profile_dir)).to be(true)

      files = Dir.glob("#{profile_dir}/*")
      expect(files.length).to be >= 2
    end

    it "generates graph_html and stack profile files by default" do
      middleware.call(instance, job_hash, queue, &block)

      profile_dir = "#{test_dir}/TestJob"
      files = Dir.glob("#{profile_dir}/*")

      graph_html_files = files.select { |f| f.end_with?(".graph.html") }
      stack_files = files.select { |f| f.end_with?(".stack.html") }

      expect(graph_html_files.length).to eq(1)
      expect(stack_files.length).to eq(1)
    end

    it "includes the profiled method call in the generated files" do
      middleware.call(instance, job_hash, queue, &block)

      profile_dir = "#{test_dir}/TestJob"
      files = Dir.glob("#{profile_dir}/*")

      graph_html_file = files.find { |f| f.end_with?(".graph.html") }
      stack_file = files.find { |f| f.end_with?(".stack.html") }

      graph_html_content = File.read(graph_html_file)
      stack_content = File.read(stack_file)

      expect(graph_html_content).to include("test_method_to_profile")
      expect(stack_content).to include("test_method_to_profile")
    end

    context "with wrapped job class" do
      let(:job_hash) do
        {
          "class" => "ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper",
          "wrapped" => "MyWrappedJob",
          "jid" => "wrapped_jid_456",
          "enqueued_at" => Time.current.to_f
        }
      end

      it "creates directory with wrapped class name" do
        middleware.call(instance, job_hash, queue, &block)

        expect(Dir.exist?("#{test_dir}/MyWrappedJob")).to be(true)
      end

      it "generates profile files with wrapped job name" do
        middleware.call(instance, job_hash, queue, &block)

        profile_dir = "#{test_dir}/MyWrappedJob"
        files = Dir.glob("#{profile_dir}/*")

        graph_html_files = files.select { |f| f.end_with?(".graph.html") }
        stack_files = files.select { |f| f.end_with?(".stack.html") }

        expect(graph_html_files.length).to eq(1)
        expect(stack_files.length).to eq(1)
      end
    end

    context "with custom printers" do
      let(:options) do
        {
          dir: test_dir,
          printers: [:flat, :graph_html]
        }
      end

      it "generates only the specified profile formats" do
        middleware.call(instance, job_hash, queue, &block)

        profile_dir = "#{test_dir}/TestJob"
        files = Dir.glob("#{profile_dir}/*")

        flat_files = files.select { |f| f.end_with?(".flat.txt") }
        graph_html_files = files.select { |f| f.end_with?(".graph.html") }
        stack_files = files.select { |f| f.end_with?(".stack.html") }

        expect(flat_files.length).to eq(1)
        expect(graph_html_files.length).to eq(1)
        expect(stack_files.length).to eq(0)
      end

      it "includes the profiled method call in flat file" do
        middleware.call(instance, job_hash, queue, &block)

        profile_dir = "#{test_dir}/TestJob"
        files = Dir.glob("#{profile_dir}/*")

        flat_file = files.find { |f| f.end_with?(".flat.txt") }
        flat_content = File.read(flat_file)

        expect(flat_content).to include("test_method_to_profile")
      end
    end

    context "with min_percent option" do
      let(:options) do
        {
          dir: test_dir,
          min_percent: 40.0,
          printers: [:stack]
        }
      end
      let(:block) do
        lambda do
          heavy_work
          light_work
        end
      end

      it "omits methods below the threshold in the stack profile" do
        middleware.call(instance, job_hash, queue, &block)

        profile_dir = "#{test_dir}/TestJob"
        files = Dir.glob("#{profile_dir}/*.stack.html")

        expect(files.length).to eq(1)

        stack_content = File.read(files.first)

        expect(stack_content).to include("heavy_work")
        expect(stack_content).not_to include("light_work")
      end
    end
  end
end
