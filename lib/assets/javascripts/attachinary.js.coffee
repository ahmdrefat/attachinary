(($) ->
  $.attachinary =
    index: 0
    config:
      disableWith: 'Uploading...'
      indicateProgress: true
      invalidFormatMessage: 'Invalid file format'
      template: """
        <ul>
          <% for(var i=0; i<files.length; i++){ %>
            <li>
              <% if(files[i].resource_type == "raw") { %>
                <div class="raw-file"></div>
              <% } else { %>
                <img
                  src="<%= $.cloudinary.url(files[i].public_id, { "version": files[i].version, "format": 'jpg', "crop": 'fill', "width": 75, "height": 75 }) %>"
                  alt="" width="75" height="75" />
              <% } %>
              <a href="#" data-remove="<%= files[i].public_id %>">Remove</a>
            </li>
          <% } %>
        </ul>
      """
      render: (files) ->
        $.attachinary.Templating.template(@template, files: files)

  $.fn.attachinary = (options) ->
    settings = $.extend {}, $.attachinary.config, options

    this.each ->
      $this = $(this)
      if !$this.data('attachinary-bond')
        $this.data 'attachinary-bond', new $.attachinary.Attachinary($this, settings)

  class $.attachinary.Attachinary
    constructor: (@$input, @config) ->
      @options = @$input.data('attachinary')

      if @config.files
        @$input.data('attachinary').files = @config.files

      @files = @options.files

      @$cors = @$input.data('cors')
      @$autoSave = @$input.data('auto-save')
      @$addDescription = @$input.data('add-description')

      @$form = @$input.closest('form')
      @$submit = @$form.find(@options.submit_selector ? 'input[type=submit]')
      @$wrapper = @$input.closest(@options.wrapper_container_selector) if @options.wrapper_container_selector?

      @initFileUpload()
      @addFilesContainer()
      @bindEventHandlers()
      @redraw()
      @checkMaximum()

    initFileUpload: ->
      @options.field_name = @$input.attr('name')

      options =
        dataType: 'json'
        paramName: 'file'
        headers: {"X-Requested-With": "XMLHttpRequest"}
        dropZone: @config.dropZone || @$input.parents(".dropzone") || @$input
        sequentialUploads: true

      if @$input.attr('accept')
        options.acceptFileTypes = new RegExp("^#{@$input.attr('accept').split(",").join("|")}$", "i")

      @$input.fileupload(options)

    bindEventHandlers: ->
      @$input.bind 'fileuploadsend', (event, data) =>
        @$input.addClass 'uploading'
        @$wrapper.addClass 'uploading' if @$wrapper?
        @$form.addClass  'uploading'

        @$input.prop 'disabled', true
        if @config.disableWith
          @$submit.each (index,input) =>
            $input = $(input)
            $input.data 'old-val', $input.val() unless $input.data('old-val')?
          @$submit.val  @config.disableWith
          @$submit.prop 'disabled', true

        !@maximumReached()


      @$input.bind 'fileuploaddone', (event, data) =>
        if (file =  @addFile(data.result))
          if @$autoSave
            @syncFiles(event.target)

      @$input.bind 'fileuploadstart', (event) =>
        # important! changed on every file upload
        @$input = $(event.target)

      @$input.bind 'fileuploadalways', (event) =>
        @$input.removeClass 'uploading'
        @$wrapper.removeClass 'uploading' if @$wrapper?
        @$form.removeClass  'uploading'

        @checkMaximum()
        if @config.disableWith
          @$submit.each (index,input) =>
            $input = $(input)
            $input.val  $input.data('old-val')
          @$submit.prop 'disabled', false


      @$input.bind 'fileuploadprogressall', (e, data) =>
        progress = parseInt(data.loaded / data.total * 100, 10)
        if @config.disableWith && @config.indicateProgress
          @$submit.val "[#{progress}%] #{@config.disableWith}"

    syncFiles: (target) ->
      if @$cors
        formURL = @$input.data('cors-put-url')
        files = @$input.parents('.attachments-box').find('.attachinary_container input').val()
        formData = { 'signal_instance[signal_documents][]': files }
      else
        form = $(target).closest('form')
        formURL = $(target).closest('form').attr('action')
        formData = { 'signal_instance[signal_documents][]': form.serializeObject()['signal_instance[signal_documents][]'] }

      $.ajax
        method: 'PUT',
        url: formURL,
        data: formData,
        success: =>
          # Note: Should we show any visual effect to the user to let them now the file was saved
        error: =>
          newFile = @files.filter((file) ->
            file.bytes != undefined
          )
          @removeFile(newFile[0].public_id, true) if newFile.length > 0
          alert('File upload failed, please try again later!');

    addFile: (file) ->
      if !@options.accept || $.inArray(file.format, @options.accept) != -1  || $.inArray(file.resource_type, @options.accept) != -1
        duplicatedFiles = @files.filter (f) ->
          (f.original_filename == file.original_filename) && (f.original_filename == file.original_filename)

        if @$addDescription
          description = prompt('Add description to file name: ' + file.original_filename)
          if description
            file.original_filename = "#{file.original_filename} (#{description})"

        if duplicatedFiles.length > 0
          answer = confirm('Do you want to overwrite this file: ' + file.original_filename)
          if answer is yes
            @removeFile(duplicatedFiles[0].public_id)
          else
            file.original_filename = "#{file.original_filename}__dup#{Math.ceil(Math.random()*10000*10000)}"

        @files.push file
        @redraw()
        @checkMaximum()
        @$input.trigger 'attachinary:fileadded', [file]
        file
      else
        alert @config.invalidFormatMessage
        false

    removeFile: (fileIdToRemove, skipSync=false) ->
      _files = []
      removedFile = null
      for file in @files
        if file.public_id == fileIdToRemove
          removedFile = file
        else
          _files.push file
      @files = _files
      @redraw()
      @checkMaximum()
      @$input.trigger 'attachinary:fileremoved', [removedFile]
      if @$autoSave and !skipSync
        @syncFiles @$input

    checkMaximum: ->
      if @maximumReached()
        @$wrapper.addClass 'disabled' if @$wrapper?
        @$input.prop('disabled', true)
      else
        @$wrapper.removeClass 'disabled' if @$wrapper?
        @$input.prop('disabled', false)

    maximumReached: ->
      @options.maximum && @files.length >= @options.maximum

    addFilesContainer: ->
      if @options.files_container_selector? and $(@options.files_container_selector).length > 0
        @$filesContainer = $(@options.files_container_selector)
      else
        @$filesContainer = $('<div class="attachinary_container">')
        @$input.after @$filesContainer

    redraw: ->
      @$filesContainer.empty()

      if @files.length > 0
        @$filesContainer.append @makeHiddenField(JSON.stringify(@files))

        @$filesContainer.append @config.render(@files)
        @$filesContainer.find('[data-remove]').on 'click', (event) =>
          event.preventDefault()
          @removeFile $(event.currentTarget).data('remove')

        @$filesContainer.show()
      else
        @$filesContainer.append @makeHiddenField(null)
        @$filesContainer.hide()

    makeHiddenField: (value) ->
      $input = $('<input type="hidden">')
      $input.attr 'name', @options.field_name
      $input.val value
      $input

  # JavaScript templating by John Resig's
  $.attachinary.Templating =
    settings:
      start:        '<%'
      end:          '%>'
      interpolate:  /<%=(.+?)%>/g

    escapeRegExp: (string) ->
      string.replace(/([.*+?^${}()|[\]\/\\])/g, '\\$1')

    template: (str, data) ->
      c = @settings
      endMatch = new RegExp("'(?=[^"+c.end.substr(0, 1)+"]*"+@escapeRegExp(c.end)+")","g")
      fn = new Function 'obj',
        'var p=[],print=function(){p.push.apply(p,arguments);};' +
        'with(obj||{}){p.push(\'' +
        str.replace(/\r/g, '\\r')
           .replace(/\n/g, '\\n')
           .replace(/\t/g, '\\t')
           .replace(endMatch,"✄")
           .split("'").join("\\'")
           .split("✄").join("'")
           .replace(c.interpolate, "',$1,'")
           .split(c.start).join("');")
           .split(c.end).join("p.push('") +
           "');}return p.join('');"
      if data then fn(data) else fn

  $(document).bind "dragover", (e) ->
    dropZone = $(".dropzone")
    foundDropzone = undefined
    timeout = window.dropZoneTimeout
    unless timeout
      dropZone.addClass "in"
    else
      clearTimeout timeout
    found = false
    node = e.target
    loop
      if $(node).hasClass("dropzone")
        found = true
        foundDropzone = $(node)
        break
      node = node.parentNode
      break unless node?
    dropZone.removeClass "in hover"
    foundDropzone.addClass "hover"  if found
    window.dropZoneTimeout = setTimeout(->
      window.dropZoneTimeout = null
      dropZone.removeClass "in hover"
    , 100)

)(jQuery)
