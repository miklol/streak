enum TodoMoveFailure {
  missingSource,
  invalidDestination,
  idConflict,
  alreadyMoved,
  changedSource,
}

class TodoMoveException implements Exception {
  const TodoMoveException(this.code);

  final TodoMoveFailure code;

  @override
  String toString() => 'To-do move failed: ${code.name}';
}
