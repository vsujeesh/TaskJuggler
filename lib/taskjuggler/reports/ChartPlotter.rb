#!/usr/bin/env ruby -w
# encoding: UTF-8
#
# = ChartPlotter.rb -- The TaskJuggler III Project Management Software
#
# Copyright (c) 2006, 2007, 2008, 2009, 2010, 2011, 2012
#               by Chris Schlaeger <chris@linux.com>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of version 2 of the GNU General Public License as
# published by the Free Software Foundation.
#

require 'taskjuggler/Painter'

class TaskJuggler

  class ChartPlotter

    def initialize(width, height, data)
      # +------------------------------------------------
      # |             ^
      # |   topMargin |             legendGap
      # |             v             <->
      # |              |               -x- foo
      # |<-leftMargin->|               -x- bar
      # |              |               <-legend
      # |              |                 Width---->
      # |              +------------
      # |             ^             <-rightMargin->
      # | bottomMargin|
      # |             v
      # +------------------------------------------------
      # <-----------------canvasWidth-------------------->
      # The width of the canvas area
      @width = width
      # The height of the canvas area
      @height = height
      # The raw data to plot as loaded from the CSV file.
      @data = data

      # The margins between the graph plotting area and the canvas borders.
      @topMargin = 30
      @bottomMargin = 30
      @leftMargin = 40
      @rightMargin = 150

      @legendGap = 20
      @markerWidth = 20
      @markerX = @width - @rightMargin + @legendGap
      @markerGap = 5
      @labelX = @markerX + @markerWidth + @markerGap
      @labelHeight = 20

      # The location of the 0/0 point of the graph plotter.
      @x0 = @leftMargin
      @y0 = @height - @bottomMargin

      @labels = []
      @yData = []
      @xData = nil
      @xMinDate = nil
      @xMaxDate = nil
      @yMinDate = nil
      @yMaxDate = nil
    end

    def generate
      analyzeData
      @painter = Painter.new(@width, @height) do |p|
        p.group(:stroke => p.color(:black), :font_size => 11) do |p|
          p.line(x2c(0), y2c(0),
                 x2c(@width - (@leftMargin + @rightMargin)), y2c(0))
          p.line(x2c(0), y2c(0),
                 x2c(0), y2c(@height - (@topMargin + @bottomMargin)))
        end
        0.upto(@yData.length - 1) do |ci|
          # Compute a unique and distinguishable color for each data set. We
          # primarily use the hue value of the HSV color space for this. It
          # has 6 main colors each 60 degrees apart from each other. After the
          # first 360 round, we shift the angle by 60 / round so we get a
          # different color set than in the previous round. Additionally, the
          # saturation is decreased with each data set.
          color = Painter::Color.new(
            (60 * (ci % 6) + (60 / (1 + ci / 6))) % 360,
            255 - (ci / 8), 230, :hsv)

          values = @yData[ci]
          p.group(:stroke_width => 3, :stroke => color, :fill => color,
                  :font_size => 11) do |p|
            lastX = lastY = nil
            # Plot markers for each x/y data pair of the set and connect the
            # dots with lines. If a y value is nil, the line will be
            # interrupted.
            values.length.times do |i|
              if values[i]
                yDate = values[i]
                xc = xDate2c(@xData[i])
                yc = yDate2c(yDate)
                p.line(lastX, lastY, xc, yc) if lastY
                setMarker(p, ci, xc, yc)
                lastX = xc
                lastY = yc
              else
                lastY = lastX = nil
              end
            end

            # Add the marker to the legend
            labelY = @topMargin + @labelHeight / 2 + ci * @labelHeight
            markerY = labelY + @labelHeight / 2
            setMarker(p, ci, @markerX + @markerWidth / 2, markerY)
            p.line(@markerX, markerY, @markerX + @markerWidth, markerY)
            p.text(@labelX, labelY + @labelHeight - 5, @labels[ci],
                   :stroke => p.color(:black), :stroke_width => 0,
                   :fill => p.color(:black))
          end
        end
      end
    end

    def to_svg
      @painter.to_svg
    end

    private

    def x2c(x)
      @x0 + x
    end

    def y2c(y)
      @y0 - y
    end

    def xDate2c(date)
      x2c(((date - @xMinDate) * (@width - (@leftMargin + @rightMargin))) /
           (@xMaxDate - @xMinDate))
    end

    def yDate2c(date)
      y2c(((date - @yMinDate) * (@height - 2 * (@topMargin + @bottomMargin))) /
          (@yMaxDate - @yMinDate))
    end

    def setMarker(p, type, x, y)
      r = 4
      case (type / 5) % 5
      when 0
        # Diamond
        points = [ [ x - r, y ],
                   [ x, y + r ],
                   [ x + r, y ],
                   [ x, y - r ],
                   [ x - r, y ] ]
        p.polyline(points)
      when 1
        # Square
        p.rect(x - r, y - r, 2 * r, 2 * r)
      when 2
        # Triangle Down
        points = [ [ x - r, y - r ],
                   [ x, y + r ],
                   [ x + r, y - r ],
                   [ x - r, y - r ] ]
        p.polyline(points)
      when 3
        # Triangle Up
        points = [ [ x - r, y + r ],
                   [ x, y - r ],
                   [ x + r, y + r ],
                   [ x - r, y + r ] ]
        p.polyline(points)
      else
        p.circle(x, y, r)
      end
    end

    def analyzeData
      # Convert the @data from a line list into a column list. Each element of
      # the list is an Array for the other dimension.
      columns = []
      ri = 0
      @data.each do |row|
        ci = 0
        row.each do |col|
          columns << [] if ri == 0
          if col.nil?
            columns[ci][ri] = nil
          else
            begin
              # Check if we can conver the cell into a TjTime object. If so we
              # use this instead of the original String or Number.
              columns[ci][ri] = TjTime.new(col)
            rescue
              # If not, we keep the original value.
              columns[ci][ri] = col.empty? ? nil : col
            end
          end
          ci += 1
        end
        ri += 1
      end

      header = true
      columns[0].each do |date|
        if header
          unless date == "Date"
            error("First column must have a 'Date' header instead of '#{date}'")
          end
          header = false
        else
          unless date.is_a?(TjTime)
            error("First column must be all dates")
          end
          @xMinDate = date if @xMinDate.nil? || date < @xMinDate
          @xMaxDate = date if @xMaxDate.nil? || date > @xMaxDate
        end
      end
      # And the xData values.
      @xData = columns[0][1..-1]

      unless @xMinDate && @xMaxDate
        error("First column does not contain valid dates.")
      end

      # Now eleminate columns that contain invalid data.
      columns[1..-1].each do |col|
        badCol = false
        col[1..-1].each do |cell|
          if cell && !cell.is_a?(TjTime)
            badCol = true
            break
          end
          # Ignore missing values
          next unless cell

          @yMinDate = cell if @yMinDate.nil? || cell < @yMinDate
          @yMaxDate = cell if @yMaxDate.nil? || cell > @yMaxDate
        end
        # Store the header of the column. It will be used as label.
        @labels << col[0]
        # Add the column values as another entry into the yData list.
        @yData << col[1..-1] unless badCol
      end

      unless @yMinDate && @yMaxDate
        error("Columns don't contain any valid dates.")
      end
    end

    def error(msg)
      raise RuntimeError, msg
    end

  end

end
