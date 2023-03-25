require 'yaml'
require "gitlab"
require 'optparse'

STATUS_CHECK_TIME = 5  #sec
RETRY_COUNT = 180

CONFIG_FILE = 'config.yml'
EXPORT_PROGRESS_FILE = "export_progress.yml"
EXPORT_STATUS_FINISHED = "finished"
EXPORT_STATUS_QUEUED = "queued"
EXPORT_STATUS_STARTED = "started"
EXPORT_STATUS_REGENERATION_IN_PROGRESS = "regeneration_in_progress"

config = YAML.load_file(CONFIG_FILE)
Gitlab.configure do |gitlab_config|
    gitlab_config.endpoint = config[:api_endpoint]
    gitlab_config.private_token = config[:access_token]
end

options = {}
OptionParser.new do |opts|
    opts.banner = 'Usage: export.rb [options]'

    opts.on("-o", "--output DIR", "Output directory path") do |dir|
        options[:output_dir] = dir
    end
    opts.on('-r', '--reset', 'Reset all download statuses to "none"') do |v|
        options[:reset] = true
    end
    opts.on("-g", "--group GRP", "Output directory path") do |grp|
        options[:group] = grp
    end
end.parse!

puts options[:group]

output_dir = options[:output_dir] || '.'
serach_group = options[:group]

# Load previous progress if exists
progress = {}
if File.exist?(EXPORT_PROGRESS_FILE)
    progress = YAML.load_file(EXPORT_PROGRESS_FILE)
end
progress[:projects] ||= []

if options[:reset]
    progress[:projects]&.each { |project| project[:download_status] = 'none' }
    YAML.dump(progress, File.open(EXPORT_PROGRESS_FILE, 'w'))
    puts 'All download statuses have been reset to "none".'
    exit
end

# プロジェクトごとにエクスポート状況を取得する
Gitlab.projects.each do |item|
    next if serach_group && item.namespace.name == serach_group
    project = progress[:projects].find { |p| p[:id] == item.id }
    if project.nil?
        # 進捗ファイルにプロジェクトが存在しない場合は新規に追加
        export_status = Gitlab.export_project_status(item.id).export_status
        project = { id: item.id, name: item.name, group_name: item.namespace.name, export_status: export_status, download_status: 'none' }
        progress[:projects].push(project)
    else
        # 進捗ファイルにプロジェクトが存在する場合はエクスポート状況を更新
        project[:export_status] = Gitlab.export_project_status(item.id).export_status
    end
end

begin
    # Export and download each project if not already exported
    progress[:projects].each do |project|
        next if serach_group && project[:group_name] == serach_group
        next if project[:download_status] == EXPORT_STATUS_FINISHED
        puts "Exporting project #{project[:name]} (ID: #{project[:id]}) in group #{project[:group_name]}"

        # Export project
        if ![EXPORT_STATUS_FINISHED, EXPORT_STATUS_REGENERATION_IN_PROGRESS].include?(project[:export_status])
            Gitlab.export_project(project[:id])
        end

        # Wait for export to complete
        count = 0
        while (count < 180 && ![EXPORT_STATUS_FINISHED, EXPORT_STATUS_REGENERATION_IN_PROGRESS].include?(project[:export_status]))
            puts "  Export status: #{project[:export_status]}. Retrying in 5 seconds..."
            sleep STATUS_CHECK_TIME
            project[:export_status] = Gitlab.export_project_status(project[:id]).export_status
            count += 1
        end

        # Check if export timed out
        if count >= RETRY_COUNT
            puts "Export timeout. Skipping project #{project[:name]}."
            next
        end

        # Download project
        puts "Downloading project #{project[:name]}..."
        response = Gitlab.exported_project_download(project[:id])
        delimiter = "\";"
        filename = response.to_h[:filename].slice(0, response.to_h[:filename].index(delimiter))
        data = response.to_h[:data].read
        File.open(File.join(output_dir, filename), 'wb') do |file|
            file.write(data)
        end
        project[:download_status] = EXPORT_STATUS_FINISHED

        # Save progress
        puts "Project #{project[:name]} exported and downloaded successfully."
        puts ""
    end
rescue => e
    puts e.inspect
ensure
    YAML.dump(progress, File.open(EXPORT_PROGRESS_FILE, 'w'))
end

puts "All projects have been exported and downloaded."
