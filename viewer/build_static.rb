#!/usr/bin/env ruby
# encoding: utf-8
# Static site generator for Rails Seniority Coach
# Generates static HTML files for GitHub Pages deployment

Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

require 'erb'
require 'fileutils'
require 'yaml'
require 'json'
require 'redcarpet'
require 'rouge'
require 'rouge/plugins/redcarpet'
require 'ostruct'

# Custom Markdown renderer with syntax highlighting
class HTMLWithRouge < Redcarpet::Render::HTML
  include Rouge::Plugins::Redcarpet
end

# ERB context that provides yield functionality
class ERBContext < OpenStruct
  def get_binding
    binding
  end

  def yield
    @_yield_content
  end
end

class StaticSiteBuilder
  attr_reader :output_dir, :content_dir, :config_dir, :views_dir

  def initialize
    @output_dir = File.join(File.dirname(__FILE__), 'dist')
    @content_dir = File.join(File.dirname(__FILE__), '..', 'content')
    @config_dir = File.join(File.dirname(__FILE__), '..', 'config', 'skills')
    @views_dir = File.join(File.dirname(__FILE__), 'views')
  end

  def build
    puts "🏗️  Building static site..."

    # Clean and create output directory
    FileUtils.rm_rf(output_dir)
    FileUtils.mkdir_p(output_dir)

    # Load all tracks
    tracks = load_tracks

    # Build search index
    search_index = build_search_index(tracks)

    # Generate index page
    generate_index(tracks, search_index)

    # Generate track pages
    tracks.each do |track|
      generate_track_page(track, tracks, search_index)

      # Generate topic pages for this track
      topics = load_track_topics(track['key'])
      topics.each do |topic|
        generate_topic_page(track, topic, topics, tracks, search_index)
      end
    end

    puts "✅ Static site built successfully!"
    puts "📂 Output directory: #{output_dir}"
    puts "📄 Generated #{count_html_files} HTML files"
  end

  private

  def load_tracks
    tracks_file = File.join(config_dir, 'tracks.yml')
    YAML.load_file(tracks_file)['tracks']
  end

  def load_track_topics(track_key)
    track_dir = File.join(config_dir, track_key)
    return [] unless Dir.exist?(track_dir)

    Dir.glob(File.join(track_dir, '*.yml')).map do |file|
      data = YAML.load_file(file)
      if data.nil?
        puts "⚠️  Warning: Invalid YAML file: #{file}"
        next
      end

      # Handle both 'topic' and 'skill' keys (legacy)
      topic_data = data['topic'] || data['skill']
      if topic_data.nil?
        puts "⚠️  Warning: No topic/skill key found in: #{file}"
        next
      end

      # Normalize the data (skill files use 'title' instead of 'name')
      topic_data['name'] ||= topic_data['title']
      topic_data
    end.compact.sort_by { |t| t['name'] }
  end

  def load_topic_content(track_key, topic_key)
    base_path = File.join(content_dir, track_key, topic_key)

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

  def find_adjacent_topics(topics, current_topic_key)
    current_index = topics.find_index { |t| t['key'] == current_topic_key }
    return { prev: nil, next: nil } unless current_index

    {
      prev: current_index > 0 ? topics[current_index - 1] : nil,
      next: current_index < topics.length - 1 ? topics[current_index + 1] : nil
    }
  end

  def build_search_index(tracks)
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
          url: "/tracks/#{track['key']}/topics/#{topic['key']}.html"
        }
      end
    end
    index
  end

  def markdown(text)
    return '' unless text
    # Force UTF-8 encoding
    text = text.encode('UTF-8', invalid: :replace, undef: :replace)

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

  def render_template(template_name, vars = {})
    template_path = File.join(views_dir, "#{template_name}.erb")
    template = File.read(template_path, encoding: 'UTF-8')

    # Set instance variables for ERB template
    vars.each do |key, value|
      instance_variable_set("@#{key}", value)
    end

    ERB.new(template, trim_mode: '-').result(binding)
  end

  def render_with_layout(content, vars = {})
    layout_path = File.join(views_dir, 'layout.erb')
    layout_template = File.read(layout_path, encoding: 'UTF-8')

    # Replace <%= yield %> with <%= @_yield_content %> to avoid keyword conflict
    layout_template = layout_template.gsub('<%= yield %>', '<%= @_yield_content %>')

    # Set instance variables
    instance_variable_set(:@_yield_content, content)
    vars.each do |key, value|
      instance_variable_set("@#{key}", value)
    end

    ERB.new(layout_template, trim_mode: '-').result(binding)
  end

  # Helper method for params (used in templates)
  def params
    @params || {}
  end

  def generate_index(tracks, search_index)
    puts "📄 Generating index.html..."

    # Render index template
    content = render_template('index', tracks: tracks)

    # Wrap with layout
    html = render_with_layout(content, search_index: search_index)

    # Write to file
    File.write(File.join(output_dir, 'index.html'), html)
  end

  def generate_track_page(track, all_tracks, search_index)
    puts "📄 Generating track: #{track['name']}..."

    topics = load_track_topics(track['key'])

    # Create track directory
    track_dir = File.join(output_dir, 'tracks', track['key'])
    FileUtils.mkdir_p(track_dir)

    # Render track template
    content = render_template('track', track: track, topics: topics)

    # Wrap with layout
    html = render_with_layout(content,
      search_index: search_index,
      params: { track_key: track['key'] }
    )

    # Write to file
    File.write(File.join(track_dir, 'index.html'), html)
  end

  def generate_topic_page(track, topic, all_topics, all_tracks, search_index)
    puts "  📄 Generating topic: #{topic['name']}..."

    # Create topic directory
    topic_dir = File.join(output_dir, 'tracks', track['key'], 'topics')
    FileUtils.mkdir_p(topic_dir)

    # Load topic content
    content_data = load_topic_content(track['key'], topic['key'])

    # Find adjacent topics
    adjacent = find_adjacent_topics(all_topics, topic['key'])

    # Render topic template
    content_html = render_template('topic',
      topic_config: topic,
      content: content_data,
      adjacent: adjacent,
      track: track,
      params: {
        track_key: track['key'],
        topic_key: topic['key']
      }
    )

    # Wrap with layout
    html = render_with_layout(content_html,
      search_index: search_index,
      params: {
        track_key: track['key'],
        topic_key: topic['key']
      }
    )

    # Write to file
    File.write(File.join(topic_dir, "#{topic['key']}.html"), html)
  end

  def count_html_files
    Dir.glob(File.join(output_dir, '**', '*.html')).count
  end
end

# Run the builder
if __FILE__ == $0
  builder = StaticSiteBuilder.new
  builder.build
end
