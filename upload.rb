require 'bundler'
require 'spreadsheet'
require_relative 'flickr'
require 'pp'

$debug = true

class InvalidPhoto
  attr_reader :error

  def initialize(filename:, error:)
    @filename = filename
    @error = error
  end
  
  def valid?
    false
  end
end

class Photo
  attr_reader :filename, :title, :description, :latin, :tags

  def initialize(filename:, swedish:, english:, latin:, tags:)
    @filename = filename
    @file = Pathname.new(filename)
    @original_file_text = @file.basename(@file.extname).to_s
    @swedish = swedish
    @english = english
    @latin = latin
    @tags = tags || []
    @tags = [@swedish, @english] + tags + [@latin]
    @title = "#{@swedish} / #{@english}"
    @description = "Scientific name: #{@latin}\nOriginal file: #{@original_file_text}\n"
  end

  def valid?
    @swedish && @english && @latin && @tags && !@tags.empty? && @name != ' / '
  end

  def error
    "Unknown error"
  end
end

class Uploader
  def initialize(token_file:, directory:)
    prepare_metadata("#{directory}/names.xls")
    check_photos(directory)
    if !valid?
      exit
    end
    setup_flickr(token_file)
    upload_photos
  end

  def setup_flickr(token_file)
    @flickr = Flickr.new(token_file)
    fetch_albums
  end

  def fetch_albums
    @albums = {}
    @flickr.photosets.each do |album| 
      @albums[album.title] = album
    end
  end

  def upload_photos
    @albums_to_reorder = []
    @photos.each do |photo| 
      upload_photo(photo)
    end
    @albums_to_reorder.uniq.each do |album_title| 
      pp ["REORDER_ALBUM", album_title] if $debug
      @albums[album_title].reorder
    end
  end

  def upload_photo(photo)
    pp ["UPLOAD", photo.filename, photo.title] if $debug
    photo_id = @flickr.upload_photo(photo.filename, photo.title, photo.description, photo.tags)
    pp ["UPLOADED_AS", photo_id] if $debug
    album = @albums[photo.title]
    if album
      pp ["ADD_TO_ALBUM", album.title, photo_id] if $debug
      album.add_photo(photo_id)
    else
      pp ["CREATE_ALBUM", photo.title] if $debug
      create_album(photo.title, "Scientific name: #{photo.latin}\n", photo_id)
      album = @albums[photo.title]
    end
    @albums_to_reorder << photo.title
  end

  def create_album(title, description, cover_photo_id)
    album_id = @flickr.create_photoset(title, description, cover_photo_id)
    fetch_albums
    album_id
  end

  def check_photos(directory)
    pwd = Dir.pwd
    Dir.chdir(directory)
    files = Dir.glob("*/*/*.jpg")
    files += Dir.glob("*/*/*.jpeg")
    files += Dir.glob("*/*/*.JPG")
    files += Dir.glob("*/*/*.JPEG")
    files += Dir.glob("*/*/*.Jpg")
    files += Dir.glob("*/*/*.Jpeg")
    Dir.chdir(pwd)
    @photos = files.map do |filename|
      birdcode,tagcode,_file = filename.split("/")
      bird = @birds[birdcode]
      tags = @tags[tagcode]
      photo = nil
      if !bird
        photo = InvalidPhoto.new(filename: "#{directory}/#{filename}", error: "Could not find bird data for #{birdcode}")
      elsif !tags || tags.empty?
        photo = InvalidPhoto.new(filename: "#{directory}/#{filename}", error: "Could not find tags for #{tagcode}")
      else
        photo = Photo.new(filename: "#{directory}/#{filename}", swedish: bird[:swedish], english: bird[:english], latin: bird[:latin], tags: tags)
      end

      if !photo.valid?
        puts "File: #{filename} is invalid: #{photo.error}"
        @invalid = true
      end
      photo
    end
  end

  def valid?
    !@invalid
  end

  def prepare_metadata(names_file)
    Spreadsheet.client_encoding = 'UTF-8'
    begin
      book = Spreadsheet.open(names_file)
    rescue Errno::ENOENT
      puts "Could not find #{names_file}"
      exit
    end
    birds = book.worksheet('Birds')
    if birds.nil?
      puts "#{names_file} has no sheet named Birds"
      exit
    end
    tags = book.worksheet('Tags')
    if tags.nil?
      puts "#{names_file} has no sheet named Tags"
      exit
    end

    @birds = {}
    birds.each do |row| 
      code,swedish,english,latin = row
      if !code || code.empty?
        if swedish || english || latin
          puts "Missing code for {#{swedish}, #{english}, #{latin}}"
          exit
        end
      else
        if !swedish || swedish.empty?
          puts "Missing swedish name for #{code}"
          exit
        end
        if !english || english.empty?
          puts "Missing english name for #{code}"
          exit
        end
        if !latin || latin.empty?
          puts "Missing latin name for #{code}"
          exit
        end
      end
      @birds[code] = {
        swedish: swedish,
        english: english,
        latin: latin
      }
    end

    @tags = {}
    tags.each(1) do |row| 
      code,*taglist = row
      taglist = taglist.compact
      if !code || code.empty?
        if !taglist.empty?
          puts "Missing code for #{taglist.inspect}"
          exit
        end
      else
        if !taglist || taglist.empty?
          puts "Missing tags for #{code}"
        end
      end
      @tags[code] = taglist
    end
  end
end

if __FILE__ == $0
  Uploader.new(token_file: "oauthtokens-sbfltest.yml", directory: "data")
end