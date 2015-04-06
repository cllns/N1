Reflux = require 'reflux'
_ = require 'underscore-plus'
SearchView = require './search-view'

{DatabaseStore,
 DatabaseView,
 NamespaceStore,
 WorkspaceStore,
 AddRemoveTagsTask,
 FocusedTagStore,
 FocusedThreadStore,
 Actions,
 Utils,
 Thread,
 Message} = require 'inbox-exports'

ThreadStore = Reflux.createStore
  init: ->
    @_resetInstanceVars()

    @listenTo Actions.searchQueryCommitted, @_onSearchCommitted
    @listenTo Actions.selectLayoutMode, @_autoselectForLayoutMode

    @listenTo Actions.archiveAndPrevious, @_onArchiveAndPrev
    @listenTo Actions.archiveAndNext, @_onArchiveAndNext
    @listenTo Actions.archiveCurrentThread, @_onArchive

    @listenTo DatabaseStore, @_onDataChanged
    @listenTo FocusedTagStore, @_onTagChanged
    @listenTo NamespaceStore, @_onNamespaceChanged

  _resetInstanceVars: ->
    @_lastQuery = null
    @_searchQuery = null

  view: ->
    @_view

  setView: (view) ->
    @_viewUnlisten() if @_viewUnlisten
    @_view = view

    @_viewUnlisten = @_view.listen ->
      @trigger(@)
      @_autoselectForLayoutMode()
    ,@

    @trigger(@)

  createView: ->
    tagId = FocusedTagStore.tagId()
    namespaceId = NamespaceStore.current()?.id

    if @_searchQuery
      @setView(new SearchView(@_searchQuery, namespaceId))

    else if namespaceId and tagId
      matchers = []
      matchers.push Thread.attributes.namespaceId.equal(namespaceId)
      matchers.push Thread.attributes.tags.contains(tagId) if tagId isnt "*"
      @setView new DatabaseView Thread, {matchers}, (item) ->
        DatabaseStore.findAll(Message, {threadId: item.id})

    Actions.focusThread(null)

  # Inbound Events

  _onTagChanged: -> @createView()
  _onNamespaceChanged: -> @createView()

  _onSearchCommitted: (query) ->
    @_searchQuery = query
    @createView()

  _onDataChanged: (change) ->
    if change.objectClass is Thread.name
      @_view.invalidate({shallow: true})

    if change.objectClass is Message.name
      threadIds = _.uniq _.map change.objects, (m) -> m.threadId
      @_view.invalidateItems(threadIds)

  _onArchive: ->
    @_archiveAndShiftBy('auto')

  _onArchiveAndPrev: ->
    @_archiveAndShiftBy(-1)

  _onArchiveAndNext: ->
    @_archiveAndShiftBy(1)

  _archiveAndShiftBy: (offset) ->
    layoutMode = WorkspaceStore.selectedLayoutMode()
    selected = FocusedThreadStore.thread()
    return unless selected

    # Determine the index of the current thread
    index = @_view.indexOfId(selected.id)
    return if index is -1

    # Archive the current thread
    task = new AddRemoveTagsTask(selected.id, ['archive'], ['inbox'])
    Actions.postNotification({message: "Archived thread", type: 'success'})
    Actions.queueTask(task)

    if offset is 'auto'
      if layoutMode is 'list'
        # If the user is in list mode, return to the thread lit
        Actions.focusThread(null)
        return
      else if layoutMode is 'split'
        # If the user is in split mode, automatically select another
        # thead when they archive the current one. We move up if the one above
        # the current thread is unread. Otherwise move down.
        thread = @_view.get(index - 1)
        if thread?.isUnread()
          offset = -1
        else
          offset = 1

    index = Math.min(Math.max(index + offset, 0), @_view.count() - 1)
    Actions.focusThread(@_view.get(index))

  _autoselectForLayoutMode: ->
    selectedId = FocusedThreadStore.threadId()
    if WorkspaceStore.selectedLayoutMode() is "split" and not selectedId
      _.defer => Actions.focusThread(@_view.get(0))


module.exports = ThreadStore