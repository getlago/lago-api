namespace :upgrade_verification do
  desc "Verifies the current system's readiness for an upgrade and outlines necessary migration paths"
  task :verify_and_guide => :environment do
    current_version = fetch_current_version('config/versions.yml')
    target_versions_data = load_versions_data('config/to_versions.yml')

    target_versions = target_versions_data['versions']

    if can_upgrade_directly?(current_version, target_versions)
      puts "Direct upgrade possible to version #{latest_version(target_versions)}"
    else
      migration_path = determine_migration_path(current_version, target_versions)
      puts "Upgrade path needed: #{migration_path.join(' -> ')}"
    end
  end

  private

  def fetch_current_version(file_path)
    yaml_data = YAML.load_file(file_path)
    yaml_data['versions'].last['version']
  end

  def load_versions_data(file_path)
    YAML.load_file(file_path)
  end

  def latest_version(versions)
    versions.last['version']
  end

  def can_upgrade_directly?(current_version, target_versions)
    current_index = target_versions.find_index { |v| v['version'] == current_version }
    return false if current_index.nil?

    target_versions[current_index + 1..-1].all? { |v| v['migrations'].empty? }
  end

  def determine_migration_path(current_version, target_versions)
    path = []
    version_found = false

    target_versions.each do |version|
      version_found = true if version['version'] == current_version

      if version_found && version['migrations'].any?
        path << version['version']
      end
    end

    # Ensure the last version is included in the path if it has migrations
    path << latest_version(target_versions) if path.empty? || path.last != latest_version(target_versions)

    path
  end
end
