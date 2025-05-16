# frozen_string_literal: true

module Bidi2pdf
  module TestHelpers
    module Images
      # rubocop: disable  Metrics/ModuleLength, Metrics/AbcSize
      module TIFFHelper
        # TIFF Tag IDs
        IMAGE_WIDTH = 256
        IMAGE_LENGTH = 257
        BITS_PER_SAMPLE = 258
        COMPRESSION = 259
        PHOTOMETRIC_INTERPRETATION = 262
        STRIP_OFFSETS = 273
        SAMPLES_PER_PIXEL = 277
        ROWS_PER_STRIP = 278
        STRIP_BYTE_COUNTS = 279
        PLANAR_CONFIGURATION = 284
        INK_SET = 332

        # TIFF Data Types
        TYPE_SHORT = 3
        TYPE_LONG = 4

        # TIFF Compression Types
        COMPRESSION_NONE = 1
        COMPRESSION_CCITT_G3 = 3
        COMPRESSION_CCITT_G4 = 4

        # TIFF Photometric Interpretations
        PHOTO_WHITE_IS_ZERO = 0
        PHOTO_BLACK_IS_ZERO = 1
        PHOTO_RGB = 2
        PHOTO_SEPARATION = 5

        # Planar Configuration
        PLANAR_CHUNKY = 1

        def tiff_header(hash, data)
          cs_entry = hash[:ColorSpace]

          cs = if cs_entry.is_a?(Array) && cs_entry.first == :ICCBased
                 icc_stream = cs_entry[1]
                 icc_stream.hash[:Alternate]
               else
                 cs_entry
               end

          case cs
          when :DeviceCMYK then tiff_header_for_CMYK(hash, data)
          when :DeviceGray then tiff_header_for_gray(hash, data)
          when :DeviceRGB then tiff_header_for_rgb(hash, data)
          else
            logger.warn("Unsupported color space '#{cs}' for compressed image with filter '#{hash[:Filter]}'. Skipping image.")
            nil # Skip processing this image
          end
        end

        # See:
        #    * https://gist.github.com/gstorer/f6a9f1dfe41e8e64dcf58d07afa9ab2a
        #    * https://github.com/yob/pdf-reader/blob/main/examples/extract_images.rb
        def pack_tiff(entries)
          fields = entries.size
          fmt = [
            "a2", # Byte order ("II")
            "S<", # TIFF magic (42)
            "L<", # Offset to first IFD (8)
            "S<", # Number of directory entries
            ("S< S< L< L<" * fields), # each tag: id, type, count, value
            "L<" # Next IFD offset (0 = end)
          ].join(" ")

          # Build the flat array: ['II', 42, 8, fields, tag1, type1, count1, value1, …, 0]
          values = ["II", 42, 8, fields] + entries.flatten + [0]
          values.pack(fmt)
        end

        def tiff_header_for_gray(hash, data)
          width = hash[:Width]
          height = hash[:Height]
          bpc = hash[:BitsPerComponent] || 8
          img_size = data.bytesize

          # 9 tags, no extra arrays needed
          fields = 9
          # size of header+IFD before the image data starts
          header_ifd_size = 2 + 2 + 4 + 2 + (fields * 12) + 4
          data_offset = header_ifd_size

          entries = [
            [IMAGE_WIDTH, TYPE_LONG, 1, width], # ImageWidth
            [IMAGE_LENGTH, TYPE_LONG, 1, height], # ImageLength
            [BITS_PER_SAMPLE, TYPE_SHORT, 1, bpc], # BitsPerSample
            [COMPRESSION, TYPE_SHORT, 1, COMPRESSION_NONE], # Compression (1 = none)
            [PHOTOMETRIC_INTERPRETATION, TYPE_SHORT, 1, PHOTO_BLACK_IS_ZERO], # PhotometricInterpretation (1 = BlackIsZero)
            [STRIP_OFFSETS, TYPE_LONG, 1, data_offset], # StripOffsets
            [SAMPLES_PER_PIXEL, TYPE_SHORT, 1, 1], # SamplesPerPixel
            [STRIP_BYTE_COUNTS, TYPE_LONG, 1, img_size], # StripByteCounts
            [PLANAR_CONFIGURATION, TYPE_SHORT, 1, PLANAR_CHUNKY] # PlanarConfiguration (1 = chunky)
          ]

          pack_tiff(entries)
        end

        def tiff_header_for_ccitt(hash, data)
          dp = hash[:DecodeParms] || {}
          width = dp[:Columns] || hash[:Width]
          height = hash[:Height]
          k = dp[:K] || 0
          group = (k.positive? ? COMPRESSION_CCITT_G3 : COMPRESSION_CCITT_G4)
          img_size = data.bytesize

          # We’ll emit exactly 8 tags:
          fields = 8
          # Calculate where the image data will start:
          header_size = 2 + 2 + 4 + 2 + (fields * 12) + 4

          entries = [
            [IMAGE_WIDTH, TYPE_LONG, 1, width], # ImageWidth
            [IMAGE_LENGTH, TYPE_LONG, 1, height], # ImageLength
            [BITS_PER_SAMPLE, TYPE_SHORT, 1, 1], # BitsPerSample
            [COMPRESSION, TYPE_SHORT, 1, group], # Compression (3=G3, 4=G4)
            [PHOTOMETRIC_INTERPRETATION, TYPE_SHORT, 1, PHOTO_WHITE_IS_ZERO], # PhotometricInterpretation (0 = WhiteIsZero)
            [STRIP_OFFSETS, TYPE_LONG, 1, header_size], # StripOffsets
            [ROWS_PER_STRIP, TYPE_LONG, 1, height], # RowsPerStrip
            [STRIP_BYTE_COUNTS, TYPE_LONG, 1, img_size] # StripByteCounts
          ]

          pack_tiff(entries)
        end

        def tiff_header_for_cmyk(hash, data)
          width = hash[:Width]
          height = hash[:Height]
          bpc = hash[:BitsPerComponent] || 8
          img_size = data.bytesize

          # CMYK needs 10 tags + a 4×SHORT BitsPerSample array
          fields = 10
          bits_array_size = 4 * 2 # 4 channels × 2 bytes each

          # Size of header + IFD (before the bits array)
          header_ifd_size = 2 + 2 + 4 + 2 + (fields * 12) + 4
          # Where the pixel data will really start:
          data_offset = header_ifd_size + bits_array_size

          entries = [
            [IMAGE_WIDTH, TYPE_LONG, 1, width], # ImageWidth
            [IMAGE_LENGTH, TYPE_LONG, 1, height], # ImageLength
            [BITS_PER_SAMPLE, TYPE_SHORT, 4, header_ifd_size], # BitsPerSample (pointer to array)
            [COMPRESSION, TYPE_SHORT, 1, COMPRESSION_NONE], # Compression (1 = none)
            [PHOTOMETRIC_INTERPRETATION, TYPE_SHORT, 1, PHOTO_SEPARATION], # PhotometricInterpretation (5 = Separation)
            [STRIP_OFFSETS, TYPE_LONG, 1, data_offset], # StripOffsets
            [SAMPLES_PER_PIXEL, TYPE_SHORT, 1, 4], # SamplesPerPixel
            [STRIP_BYTE_COUNTS, TYPE_LONG, 1, img_size], # StripByteCounts
            [PLANAR_CONFIGURATION, TYPE_SHORT, 1, PLANAR_CHUNKY], # PlanarConfiguration (1 = chunky)
            [INK_SET, TYPE_SHORT, 1, 1] # InkSet (1 = CMYK)
          ]

          header = pack_tiff(entries)
          # Append the 4-channel BitsPerSample array as little‐endian SHORTs:
          header << [bpc, bpc, bpc, bpc].pack("S<S<S<S<")
          header
        end

        def tiff_header_for_rgb(hash, data)
          width = hash[:Width]
          height = hash[:Height]
          bpc = hash[:BitsPerComponent] || 8
          img_size = data.bytesize

          # 8 tags + a 3×SHORT BitsPerSample array
          fields = 8
          bits_array_size = 3 * 2 # 3 channels × 2 bytes each

          # size of header + IFD before the bits array
          header_ifd_size = 2 + 2 + 4 + 2 + (fields * 12) + 4
          # where the pixel data really starts:
          data_offset = header_ifd_size + bits_array_size

          entries = [
            [IMAGE_WIDTH, TYPE_LONG, 1, width], # ImageWidth
            [IMAGE_LENGTH, TYPE_LONG, 1, height], # ImageLength
            [BITS_PER_SAMPLE, TYPE_SHORT, 3, header_ifd_size], # BitsPerSample → pointer to our array
            [COMPRESSION, TYPE_SHORT, 1, COMPRESSION_NONE], # Compression (1 = none)
            [PHOTOMETRIC_INTERPRETATION, TYPE_SHORT, 1, PHOTO_RGB], # PhotometricInterpretation (2 = RGB)
            [STRIP_OFFSETS, TYPE_LONG, 1, data_offset], # StripOffsets
            [SAMPLES_PER_PIXEL, TYPE_SHORT, 1, 3], # SamplesPerPixel
            [STRIP_BYTE_COUNTS, TYPE_LONG, 1, img_size] # StripByteCounts
          ]

          # pack the IFD
          header = pack_tiff(entries)

          # append the 3-channel BitsPerSample as little-endian SHORTs
          header << [bpc, bpc, bpc].pack("S<S<S<")

          header
        end
      end
    end
    # rubocop: enable Metrics/ModuleLength, Metrics/AbcSize
  end
end
