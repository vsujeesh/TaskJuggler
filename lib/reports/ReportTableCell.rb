#!/usr/bin/env ruby -w
# encoding: UTF-8
#
# = ReportTableCell.rb -- The TaskJuggler III Project Management Software
#
# Copyright (c) 2006, 2007, 2008, 2009 by Chris Schlaeger <cs@kde.org>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of version 2 of the GNU General Public License as
# published by the Free Software Foundation.
#

class TaskJuggler

  # This class models the output format independent version of a cell in a
  # TableReport. It belongs to a certain ReportTableLine and
  # ReportTableColumn. Normally a cell contains text on a colored background.
  # By help of the @special variable it can alternatively contain any object
  # the provides the necessary output methods such as to_html.
  class ReportTableCell

    attr_reader :line, :text, :tooltip, :query
    attr_accessor :data, :url, :category, :hidden, :alignment, :padding,
                  :indent, :icon, :fontSize, :fontColor, :bold, :width,
                  :rows, :columns, :special

    # Create the ReportTableCell object and initialize the attributes to some
    # default values. _line_ is the ReportTableLine this cell belongs to. _text_
    # is the text that should appear in the cell. _headerCell_ is a flag that
    # must be true only for table header cells.
    def initialize(line, text = '', query = nil, headerCell = false)
      @line = line
      @line.addCell(self) if line

      @headerCell = headerCell
      # The cell textual content. This may be a String or a
      # RichTextIntermediate object.
      @text = nil
      # A copy of a Query object that is needed to access project data via the
      # query function.
      @query = query ? query.dup : nil
      # A custom text for the tooltip.
      @tooltip = nil
      self.text = text
      # A URL that is associated with the content of the cell.
      @url = nil
      # The original data of the cell content (optional, nil if not provided)
      @data = nil
      @category = nil
      @hidden = false
      # How to horizontally align the cell
      @alignment = :center
      # Horizontal padding between frame and cell content
      @padding = 3
      # Whether or not to indent the cell. If not nil, it is a Fixnum
      # indicating the indentation level.
      @indent = nil
      # The basename of the icon file
      @icon = nil
      @fontSize = nil
      @fontColor = 0x000000
      @bold = false
      @width = nil
      @rows = 1
      @columns = 1
      # Ignore everything and use this reference to generate the output.
      @special = nil
    end

    def text=(text)
      if text.is_a?(RichTextIntermediate)
        text.functionHandler('query').setQuery(@query)
      end
      @text = text
    end


    def tooltip=(text)
      @tooltip = text
      text.functionHandler('query').setQuery(@query)
    end

    # Return true if two cells are similar enough so that they can be merged in
    # the report to a single, wider cell. _c_ is the cell to compare this cell
    # with.
    def ==(c)
      @text == c.text &&
      @alignment == c.alignment &&
      @padding == c.padding &&
      @indent == c.indent &&
      @category == c.category
    end

    # Turn the abstract cell representation into an HTML element tree.
    def to_html
      return nil if @hidden
      return @special.to_html if @special

      # Determine cell attributes
      attribs = { }
      attribs['rowspan'] = "#{@rows}" if @rows > 1
      attribs['colspan'] = "#{@columns}" if @columns > 1
      attribs['class'] = @category ? @category : 'tabcell'
      cell = XMLElement.new('td', attribs)

      # Determine cell style
      alignSymbols = [ :left, :center, :right ]
      aligns = %w( left center right)
      style = "text-align:#{aligns[alignSymbols.index(@alignment)]}; "
      paddingLeft = paddingRight = 0
      if @indent && @alignment != :center
        if @alignment == :left
          paddingLeft = @padding + @indent * 8
          paddingRight = @padding
        elsif @alignment == :right
          paddingLeft = @padding
          paddingRight = @padding + (@line.table.maxIndent - @indent) * 8
        end
        style += "padding-left:#{paddingLeft}px; " unless paddingLeft == 3
        style += "padding-right:#{paddingRight}px; " unless paddingRight == 3
      elsif @padding != 3
        style += "padding-left:#{@padding}px; padding-right:#{@padding}px; "
        paddingLeft = paddingRight = @padding
      end
      style += "width:#{@width - paddingLeft - paddingRight}px; " if @width
      style += 'font-weight:bold; ' if @bold
      style += "font-size: #{@fontSize}px; " if fontSize
      unless @fontColor == 0
        style += "color:#{'#%06X' % @fontColor}; "
      end
      if @longText && @line && @line.table.equiLines
        style += "height:#{@line.height - 3}px; "
      end
      cell << (div = XMLElement.new('div',
        'class' => @category ? 'celldiv' : 'headercelldiv', 'style' => style))

      if @icon
        div << XMLElement.new('img', 'src' => "icons/#{@icon}.png",
                                     'align' => 'top',
                                     'style' => 'margin-right:3px;' +
                                                'margin-bottom:2px')
      end

      return cell if @text.nil?

      tooltip = nil
      if (@line && @line.table.equiLines) || !@category || @width
        # The cell is size-limited. We only put a shortened plain-text version
        # in the cell and provide the full content via a tooltip.
        shortText = shortVersion(@text)
        if url
          div << (a = XMLElement.new('a', 'href' => @url))
          a << XMLText.new(shortText)
        else
          div << XMLText.new(shortText)
        end
        if @text != shortText
          tooltip = if @text.is_a?(RichTextIntermediate)
                      @text
                    else
                      XMLText.new(shortText)
                    end
        end
      else
        # The cell will adjust to the size of the content.
        if @text.is_a?(RichTextIntermediate)
          div << @text.to_html
        else
          if url
            div << (a = XMLElement.new('a', 'href' => @url))
            a << XMLText.new(shortText)
          else
            div << XMLText.new(shortText)
          end
        end
      end

      # Overwrite the tooltip if the user has specified a custom tooltip.
      tooltip = @tooltip if @tooltip
      if tooltip
        div['onmouseover'] = "TagToTip('#{cell.object_id}')"
        div['onmouseout'] = 'UnTip()'
        div << (ltDiv = XMLElement.new('div',
                                       'style' => 'visibility:hidden',
                                       'id' => "#{cell.object_id}"))
        ltDiv << tooltip.to_html
        div << XMLElement.new('img', 'src' => 'icons/details.png',
                              'width' => '6px',
                              'style' => 'vertical-align:top; ' +
                                         'margin:2px; ' +
                                         'top:5px')
      end

      cell
    end

    # Add the text content of the cell to an Array of Arrays form of the table.
    def to_csv(csv)
      # We only support left indentation in CSV files as the spaces for right
      # indentation will be disregarded by most applications.
      indent = @indent && @alignment == :left ? '  ' * @indent : ''
      if @special
        csv[-1] << @special.to_csv
      elsif @data && @data.is_a?(String)
        csv[-1] << indent + @data
      elsif @text
        csv[-1] << indent + shortVersion(@text)
      end
    end

    private

    # Convert a RichText String into a small one-line plain text
    # version that fits the column.
    def shortVersion(itext)
      text = itext.to_s
      modified = false
      if text.include?("\n")
        text = text[0, text.index("\n")]
        modified = true
      end
      # Assuming an average character width of 9 pixels
      if @width && (text.length > (@width / 9))
        text = text[0, @width / 9]
        modified = true
      end
      # Add three dots to show that there is more info available.
      text += "..." if modified
      text
    end

  end

end

