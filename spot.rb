require 'csv'
require 'rspotify'
require 'open3'
require 'fileutils'
require 'shellwords'
require 'mp3info'
require 'open-uri'

# Function to sanitize filenames while preserving UTF-8
def sanitize_filename(filename)
  # Only remove characters that are problematic for filenames
  filename.gsub(/[\x00\/\\:*?"<>|]/, '_')
end

# Function to get artwork data
def get_artwork_data(url)
  return nil unless url
  begin
    URI.open(url, &:read)
  rescue
    nil
  end
end

# Function to download track using yt-dlp and set ID3 tags
def download_track(track_name, artist_name, artwork_data, output_dir)
  search_query = "#{track_name} #{artist_name}"
  filename = sanitize_filename("#{artist_name} - #{track_name}")
  output_path = "#{output_dir}/#{filename}.mp3"

  command = [
    'yt-dlp',
    '--extract-audio',
    '--audio-format', 'mp3',
    '--audio-quality', '0',
    '--output', output_path,
    '--no-playlist',
    '--no-warnings',
    "ytsearch1:#{search_query}"
  ]

  puts "\nDownloading: #{track_name} by #{artist_name}"
  success = system(*command)

  if success && File.exist?(output_path)
    begin
      Mp3Info.open(output_path) do |mp3|
        mp3.tag.title = track_name
        mp3.tag.artist = artist_name

        if artwork_data
          puts "Setting artwork..."
          mp3.tag2.add_picture(artwork_data)
        end
      end
      puts "Set metadata for: #{track_name}"
    rescue => e
      puts "Warning: Could not set metadata: #{e.message}"
    end
  else
    puts "Warning: Download failed for #{track_name}"
  end
end

puts "Please enter the playlist ID:"
playlist_id = gets.chomp

# Initialize Spotify API with your credentials
RSpotify.authenticate("e50546d4ba114f9ca823624fdfac627f", "929f6368e8d7478ebc5a7394f0653cb6")

begin
  # Get playlist tracks
  playlist = RSpotify::Playlist.find_by_id(playlist_id)
  raise "Playlist not found" unless playlist

  # Create downloads directory with playlist name
  download_dir = "spotify_downloads_#{sanitize_filename(playlist.name)}"
  FileUtils.mkdir_p(download_dir)

  # Create CSV file with playlist name
  filename = "#{download_dir}/#{playlist.name.gsub(' ', '_')}_tracks.csv"
  tracks_info = []

  CSV.open(filename, 'w') do |csv|
    # Add headers
    csv << ['Track Name', 'Artist']

    # Add each track
    playlist.tracks.each do |track|
      artwork_url = track.album.images.max_by { |img| img['height'].to_i }&.fetch('url')
      track_info = [
        track.name,
        track.artists.first.name,
        artwork_url
      ]
      tracks_info << track_info
      # Only write name and artist to CSV
      csv << track_info[0..1]
    end
  end

  puts "Successfully created #{filename}"
  puts "Total tracks to download: #{tracks_info.length}"

  # Download each track
  tracks_info.each_with_index do |(track_name, artist_name, artwork_url), index|
    puts "\nProcessing track #{index + 1}/#{tracks_info.length}"
    artwork_data = get_artwork_data(artwork_url)
    download_track(track_name, artist_name, artwork_data, download_dir)
  end

  puts "\nDownload complete! Files are saved in the '#{download_dir}' directory"
rescue => e
  puts "Error: #{e.message}"
end
