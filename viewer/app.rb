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
      YAML.load_file(file)['topic']
    end.sort_by { |t| t['name'] }
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
    erb :topic
  end

  run! if app_file == $0
end
