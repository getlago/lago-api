# frozen_string_literal: true

require 'csv'

namespace :permissions do
  desc 'Generate YAML from CSV'
  task csv2yml: :environment do
    root_dir = Rails.root.join('app/config/permissions')
    table = CSV.parse(File.read("#{root_dir}/permissions.csv"), headers: true)
    default = {}
    manager = {}
    finance = {}

    table.each do |r|
      cat = r['cat'].downcase.tr(' ', '_')
      p = {
        admin: r['admin'] == '1',
        manager: r['manager'] == '1',
        finance: r['finance'] == '1',
      }

      default[cat] = {} if default[cat].nil?
      default_value = (p[:admin] && p[:manager] && p[:finance]) ? true : nil

      next unless r['name']
      names = r['name'].split(':')

      if names[1]
        default[cat][names[0]] = {} if default[cat][names[0]].nil?
        default[cat][names[0]][names[1]] = default_value
      else
        default[cat][names[0]] = default_value
      end

      next if default_value

      manager[cat] = {} if manager[cat].nil?
      finance[cat] = {} if finance[cat].nil?

      if names[1]
        manager[cat][names[0]] = {} if manager[cat][names[0]].nil?
        manager[cat][names[0]][names[1]] = p[:manager]
        finance[cat][names[0]] = {} if finance[cat][names[0]].nil?
        finance[cat][names[0]][names[1]] = p[:finance]
      else
        manager[cat][names[0]] = p[:manager]
        finance[cat][names[0]] = p[:finance]
      end
    end

    File.write Rails.root.join("#{root_dir}/definition.yml"), YAML.dump(default)
    File.write Rails.root.join("#{root_dir}/role-manager.yml"), YAML.dump(manager)
    File.write Rails.root.join("#{root_dir}/role-finance.yml"), YAML.dump(finance)
  end
end
