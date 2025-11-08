require 'sinatra'
require 'sinatra/reloader' if development?
require 'redcarpet'
require 'rouge'
require 'rouge/plugins/redcarpet'
require 'yaml'

# Custom Markdown renderer with syntax highlighting
class HTMLWithRouge < Redcarpet::Render::HTML
  include Rouge::Plugins::Redcarpet
end

class RailsSeniorityCoach < Sinatra::Base
  set :root, File.dirname(__FILE__)
  set :views, Proc.new { File.join(root, "views") }
  set :public_folder, Proc.new { File.join(root, "public") }

  # Configure Markdown renderer
  def markdown(text)
    renderer = HTMLWithRouge.new(
      hard_wrap: true,
      link_attributes: { target: "_blank" }
    )
    markdown = Redcarpet::Markdown.new(renderer,
      fenced_code_blocks: true,
      no_intra_emphasis: true,
      disable_indented_code_blocks: false,
      space_after_headers: false,
      autolink: true,
      tables: true,
      strikethrough: true
    )
    markdown.render(text)
  end

  # Load tracks
  def load_tracks
    tracks_file = File.join(settings.root, '..', 'config', 'skills', 'tracks.yml')
    YAML.load_file(tracks_file)['tracks']
  end

  # Load single track's topics
  def load_track_topics(track_key)
    track_dir = File.join(settings.root, '..', 'config', 'skills', track_key)
    return [] unless Dir.exist?(track_dir)

    Dir.glob(File.join(track_dir, '*.yml')).map do |file|
      data = YAML.load_file(file)
      # Handle both 'topic' and 'skill' keys (legacy compatibility)
      topic_data = data['topic'] || data['skill']
      next unless topic_data

      # Normalize: skill files use 'title' instead of 'name'
      topic_data['name'] ||= topic_data['title']
      topic_data
    end.compact.sort_by { |t| t['name'] }
  end

  # Load topic content
  def load_topic_content(track_key, topic_key)
    base_path = File.join(settings.root, '..', 'content', track_key, topic_key)

    {
      overview: File.exist?(File.join(base_path, 'overview.md')) ?
        File.read(File.join(base_path, 'overview.md')) : nil,
      exercise: File.exist?(File.join(base_path, 'exercise.md')) ?
        File.read(File.join(base_path, 'exercise.md')) : nil,
      checkpoint: File.exist?(File.join(base_path, 'checkpoint.yml')) ?
        YAML.load_file(File.join(base_path, 'checkpoint.yml')) : nil,
      references: File.exist?(File.join(base_path, 'references.yml')) ?
        YAML.load_file(File.join(base_path, 'references.yml')) : nil
    }
  end

  # Find previous and next topics in a track
  def find_adjacent_topics(topics, current_topic_key)
    current_index = topics.find_index { |t| t['key'] == current_topic_key }
    return { prev: nil, next: nil } unless current_index

    {
      prev: current_index > 0 ? topics[current_index - 1] : nil,
      next: current_index < topics.length - 1 ? topics[current_index + 1] : nil
    }
  end

  # Build search index for client-side search
  def build_search_index
    tracks = load_tracks
    index = []

    tracks.each do |track|
      topics = load_track_topics(track['key'])
      topics.each do |topic|
        index << {
          track_key: track['key'],
          track_name: track['name'],
          track_icon: track['icon'],
          topic_key: topic['key'],
          topic_name: topic['name'],
          depth_target: topic['depth_target'],
          objectives: topic['objectives']&.join(' ') || '',
          url: "/tracks/#{track['key']}/topics/#{topic['key']}"
        }
      end
    end

    index
  end

  # Make search index available to all views
  before do
    @search_index = build_search_index
  end

  # Routes
  get '/' do
    @tracks = load_tracks
    erb :index
  end

  get '/tracks/:track_key' do
    @tracks = load_tracks
    @track = @tracks.find { |t| t['key'] == params[:track_key] }
    halt 404 unless @track

    @topics = load_track_topics(params[:track_key])
    erb :track
  end

  get '/tracks/:track_key/topics/:topic_key' do
    @tracks = load_tracks
    @track = @tracks.find { |t| t['key'] == params[:track_key] }
    halt 404 unless @track

    @topics = load_track_topics(params[:track_key])
    @topic_config = @topics.find { |t| t['key'] == params[:topic_key] }
    halt 404 unless @topic_config

    @content = load_topic_content(params[:track_key], params[:topic_key])
    @adjacent = find_adjacent_topics(@topics, params[:topic_key])
    erb :topic
  end

  run! if app_file == $0
end
