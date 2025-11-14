# frozen_string_literal: true

require "ruby_prof"

module Sidekiq
  class RubyProfMiddleware
    def initialize(options = {})
      @dir = options.fetch(:dir, "tmp/ruby_prof")
      @min_percent = options.fetch(:min_percent, nil)
      @printers = options.fetch(:printers, [:graph_html, :stack])
    end

    def call(_instance, hash, queue, &block)
      job_dir = "#{dir}/#{hash["wrapped"] || hash["class"]}"
      FileUtils.mkdir_p(job_dir)

      result = nil
      profile = RubyProf::Profile.profile do
        result = yield
      end
      printer = RubyProf::MultiPrinter.new(profile, printers)
      printer.print(path: job_dir, profile: "#{Time.at(hash["enqueued_at"]).iso8601}-#{hash["jid"]}", min_percent: min_percent)

      result
    end

    private

    attr_reader :dir, :min_percent, :printers
  end
end
