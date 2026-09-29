import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:streak/core/data/record.dart';
import 'package:streak/core/database/local_store.dart';
import 'package:streak/features/goals/data/goal.dart';
import 'package:streak/features/todos/data/todo.dart';
import 'package:streak/features/work/data/work_area.dart';
import 'package:streak/features/work/data/work_entry.dart';
import 'package:streak/features/work/data/work_project.dart';
import 'package:streak/features/work/data/work_task.dart';
import 'package:streak/features/work/state/work_controller.dart';

import 'support/app_harness.dart';

final _at = DateTime.utc(2026, 9, 9, 12);
RecordMeta _meta(String id) => RecordMeta(id: id, createdAt: _at);
WorkController _controller() =>
    WorkController(now: () => _at.add(const Duration(hours: 1)));

Future<void> _seed(WorkController work) async {
  await work.saveArea(WorkArea(meta: _meta('area'), name: 'Client'));
  await work.saveProject(
    WorkProject(meta: _meta('project'), name: 'Website', areaId: 'area'),
  );
  await work.saveTask(
    WorkTask(
      meta: _meta('parent'),
      title: 'Build onboarding',
      projectId: 'project',
    ),
  );
  await work.saveTask(
    WorkTask(
      meta: _meta('one'),
      title: 'Write copy',
      projectId: 'project',
      parentTaskId: 'parent',
    ),
  );
  await work.saveTask(
    WorkTask(
      meta: _meta('two'),
      title: 'Design welcome',
      projectId: 'project',
      parentTaskId: 'parent',
      progressMode: WorkTaskProgress.manual,
      progress: 50,
      priority: TodoPriority.high,
    ),
  );
}

Matcher _failure(WorkFailure code) => throwsA(
  isA<WorkOperationException>().having((error) => error.code, 'code', code),
);

void main() {
  useEmptyStore();

  test('creates the hierarchy and reloads it after a cold start', () async {
    final work = _controller();
    await _seed(work);
    expect(work.areas().single.name, 'Client');
    expect(work.projects().single.name, 'Website');
    expect(work.tasks(rootsOnly: true).single.id, 'parent');
    expect(work.tasks(parentTaskId: 'parent'), hasLength(2));
    expect(work.data.projectProgress('project').fraction, .25);
    await coldStart();
    final restored = _controller();
    expect(restored.tasks(), hasLength(3));
    expect(restored.areaForTask(restored.taskById('two')!), 'area');
  });

  test(
    'title-only capture stays in the inbox and retains edited fields',
    () async {
      final work = _controller();
      var task = await work.saveTask(
        WorkTask(meta: _meta('inbox'), title: ' Idea '),
      );
      expect(task.title, 'Idea');
      expect(work.tasks(inboxOnly: true).single.id, 'inbox');
      task = await work.saveTask(
        task.copyWith(
          description: 'Details',
          completionCriteria: 'Ready',
          estimatedMinutes: 45,
          dueDate: '10-09-2026',
          dueMinute: 600,
          tags: ['draft'],
          photos: ['kept.jpg'],
          links: ['https://example.com'],
        ),
        expectedRevision: task.meta.revision,
      );
      expect(task.meta.revision, 2);
      expect(task.estimatedMinutes, 45);
      expect(task.photos, ['kept.jpg']);
      expect(LocalStore.readWork().tasks.single.toMap(), task.toMap());
    },
  );

  test('stale form saves fail without discarding another edit', () async {
    final work = _controller();
    final task = await work.saveTask(
      WorkTask(meta: _meta('task'), title: 'First'),
    );
    await work.saveTask(
      task.copyWith(title: 'Latest'),
      expectedRevision: task.meta.revision,
    );
    await expectLater(
      work.saveTask(
        task.copyWith(title: 'Stale'),
        expectedRevision: task.meta.revision,
      ),
      _failure(WorkFailure.stale),
    );
    expect(work.taskById('task')!.title, 'Latest');
  });

  test(
    'finishing a parent requires explicit consent for open subtasks',
    () async {
      final work = _controller();
      await _seed(work);
      await expectLater(
        work.setTaskStatus('parent', WorkTaskStatus.done),
        _failure(WorkFailure.openSubtasks),
      );
      expect(work.openSubtaskCount('parent'), 2);
      await work.setTaskStatus(
        'parent',
        WorkTaskStatus.done,
        completeSubtasks: true,
      );
      expect(
        work.tasks().every((task) => task.status == WorkTaskStatus.done),
        isTrue,
      );
      expect(work.taskById('two')!.progress, 100);
      expect(work.data.projectProgress('project').fraction, 1);
      await work.setTaskStatus('one', WorkTaskStatus.inProgress);
      expect(work.taskById('parent')!.status, WorkTaskStatus.inProgress);
      expect(work.taskById('one')!.completedAt, isNull);
      expect(work.entriesFor(WorkEntityKind.task, 'parent'), isNotEmpty);
    },
  );

  test(
    'closing a project and reopening work keep lifecycle consistent',
    () async {
      final work = _controller();
      await _seed(work);
      final project = work.projectById('project')!;
      await expectLater(
        work.saveProject(
          project.copyWith(status: WorkProjectStatus.done),
          expectedRevision: project.meta.revision,
        ),
        _failure(WorkFailure.openSubtasks),
      );
      await work.saveProject(
        project.copyWith(status: WorkProjectStatus.done),
        expectedRevision: project.meta.revision,
        completeTasks: true,
      );
      expect(
        work.tasks().every((task) => task.status == WorkTaskStatus.done),
        isTrue,
      );
      await work.setTaskStatus('one', WorkTaskStatus.inProgress);
      expect(work.projectById('project')!.status, WorkProjectStatus.active);
      expect(work.taskById('parent')!.status, WorkTaskStatus.inProgress);
    },
  );

  test(
    'archive is inherited and restoring a container respects child choices',
    () async {
      final work = _controller();
      await _seed(work);
      await work.setArchived(WorkEntityKind.task, 'one', true);
      await work.setArchived(WorkEntityKind.area, 'area', true);
      expect(work.areas(), isEmpty);
      expect(work.projects(), isEmpty);
      expect(work.tasks(), isEmpty);
      expect(work.tasks(archived: true), hasLength(3));
      await expectLater(
        work.setArchived(WorkEntityKind.task, 'one', false),
        _failure(WorkFailure.archivedParent),
      );
      await work.setArchived(WorkEntityKind.area, 'area', false);
      expect(
        work.tasks().map((task) => task.id),
        containsAll(['parent', 'two']),
      );
      expect(work.taskById('one')!.isArchived, isTrue);
      await work.setArchived(WorkEntityKind.task, 'one', false);
      expect(work.tasks(), hasLength(3));
    },
  );

  test(
    'moving a root carries its children without changing dates or history',
    () async {
      final work = _controller();
      await _seed(work);
      final original = work.taskById('two')!;
      await work.saveTask(
        original.copyWith(dueDate: '12-09-2026', estimatedMinutes: 90),
        expectedRevision: original.meta.revision,
      );
      await work.saveArea(WorkArea(meta: _meta('other'), name: 'Independent'));
      await work.saveProject(
        WorkProject(
          meta: _meta('other-project'),
          name: 'Other project',
          areaId: 'other',
        ),
      );
      await work.moveTask('parent', projectId: 'other-project');
      expect(work.tasks(projectId: 'project'), isEmpty);
      expect(work.tasks(projectId: 'other-project'), hasLength(3));
      expect(work.taskById('two')!.parentTaskId, 'parent');
      expect(work.taskById('two')!.dueDate, '12-09-2026');
      expect(work.taskById('two')!.estimatedMinutes, 90);
      await work.moveTask('one');
      expect(work.tasks(inboxOnly: true).single.id, 'one');
      expect(work.taskById('one')!.parentTaskId, isNull);
      expect(
        work.entriesFor(WorkEntityKind.task, 'one').single.kind,
        WorkEntryKind.scopeChange,
      );
    },
  );

  test('invalid moves never leave a partial hierarchy', () async {
    final work = _controller();
    await _seed(work);
    final before = json.encode(work.data.toMap());
    await expectLater(
      work.moveTask('parent', parentTaskId: 'one'),
      _failure(WorkFailure.invalidParent),
    );
    await expectLater(
      work.moveTask('one', parentTaskId: 'two'),
      _failure(WorkFailure.invalidParent),
    );
    await expectLater(
      work.moveTask('one', projectId: 'missing'),
      _failure(WorkFailure.invalidScope),
    );
    expect(json.encode(work.data.toMap()), before);
  });

  test(
    'moving work outside a scoped goal requires resolving the goal link',
    () async {
      final work = _controller();
      await _seed(work);
      await LocalStore.updateWork(
        (data) => data.copyWith(
          goals: [
            Goal(
              meta: _meta('goal'),
              title: 'Delivery',
              scope: GoalScope.work,
              areaId: 'area',
              source: GoalSource.work,
              measurement: GoalMeasurement.percentage,
              target: 100,
              taskIds: ['parent'],
            ),
          ],
        ),
      );
      work.reload();
      await expectLater(
        work.moveTask('parent'),
        _failure(WorkFailure.linkedGoal),
      );
      expect(work.taskById('parent')!.projectId, 'project');
    },
  );

  test(
    'duplication creates fresh work without completion or To-do provenance',
    () async {
      final work = _controller();
      await _seed(work);
      await work.setTaskStatus(
        'parent',
        WorkTaskStatus.done,
        completeSubtasks: true,
      );
      await LocalStore.updateWork(
        (data) => data.copyWith(
          tasks: [
            for (final task in data.tasks)
              if (task.id == 'parent')
                task.copyWith(sourceTodoId: 'old-todo')
              else
                task,
          ],
        ),
      );
      work.reload();
      await work.moveTaskBy('two', -1);
      final copy = await work.duplicateTask('parent', title: 'Copy');
      expect(copy.id, isNot('parent'));
      expect(copy.status, WorkTaskStatus.notStarted);
      expect(copy.sourceTodoId, isNull);
      final children = work.tasks(parentTaskId: copy.id);
      expect(children, hasLength(2));
      expect(children.map((task) => task.title), [
        'Design welcome',
        'Write copy',
      ]);
      expect(
        children.every(
          (task) => task.completedAt == null && task.progress == 0,
        ),
        isTrue,
      );
      expect(work.entriesFor(WorkEntityKind.task, copy.id), isEmpty);
      expect(work.taskById('parent')!.status, WorkTaskStatus.done);
    },
  );

  test('manual reordering persists and rejects mixed sibling groups', () async {
    final work = _controller();
    await _seed(work);
    await work.moveTaskBy('two', -1);
    expect(work.tasks(parentTaskId: 'parent').map((task) => task.id), [
      'two',
      'one',
    ]);
    await expectLater(
      work.reorderTasks([
        'parent',
        'one',
      ], expectedRevision: work.data.revision),
      _failure(WorkFailure.invalidScope),
    );
    final stale = work.data.revision;
    await work.moveTaskBy('two', 1);
    await expectLater(
      work.reorderTasks(['two', 'one'], expectedRevision: stale),
      throwsStateError,
    );
    await coldStart();
    work.reload();
    expect(work.tasks(parentTaskId: 'parent').map((task) => task.id), [
      'one',
      'two',
    ]);
  });

  test('search, filters and due sorting retain subtask context', () async {
    final work = _controller();
    await _seed(work);
    var child = work.taskById('one')!;
    await work.saveTask(
      child.copyWith(dueDate: '09-09-2026', dueMinute: 600),
      expectedRevision: child.meta.revision,
    );
    expect(work.tasks(query: 'welcome').single.id, 'two');
    expect(work.tasks(query: 'Website'), hasLength(3));
    expect(work.tasks(priority: TodoPriority.high).single.id, 'two');
    expect(work.tasks(sort: WorkTaskSort.dueDate).first.id, 'one');
    child = work.taskById('one')!;
    expect(work.isOverdue(child, DateTime(2026, 9, 9, 12)), isTrue);
    expect(work.isForToday(child, DateTime(2026, 9, 9, 12)), isTrue);
    expect(
      work.isOverdue(
        child.copyWith(clearDueMinute: true),
        DateTime(2026, 9, 9, 12),
      ),
      isFalse,
    );
    await work.setTaskStatus('parent', WorkTaskStatus.cancelled);
    expect(work.tasks(query: 'welcome', includeDone: false), isEmpty);
  });

  test(
    'notes can be edited and removed without destroying their history',
    () async {
      final work = _controller();
      await _seed(work);
      var note = await work.saveNote(
        kind: WorkEntityKind.task,
        entityId: 'parent',
        text: 'First note',
        photos: ['photo.jpg'],
      );
      note = await work.saveNote(
        kind: WorkEntityKind.task,
        entityId: 'parent',
        text: 'Updated note',
        photos: note.photos,
        existing: note,
        date: '08-09-2026',
      );
      expect(note.date, '08-09-2026');
      expect(note.meta.revision, 2);
      await work.removeNote(note.id);
      expect(work.entriesFor(WorkEntityKind.task, 'parent'), isEmpty);
      expect(work.data.entries.single.isDeleted, isTrue);
      expect(work.data.photoPaths, contains('photo.jpg'));
      await expectLater(
        work.saveNote(kind: WorkEntityKind.task, entityId: 'parent', text: ''),
        _failure(WorkFailure.invalidNote),
      );
    },
  );

  test('unknown or stale note owners are not silently ignored', () async {
    final work = _controller();
    await _seed(work);
    final note = await work.saveNote(
      kind: WorkEntityKind.project,
      entityId: 'project',
      text: 'Project note',
    );
    await work.saveNote(
      kind: WorkEntityKind.project,
      entityId: 'project',
      text: 'Latest',
      existing: note,
    );
    await expectLater(
      work.saveNote(
        kind: WorkEntityKind.project,
        entityId: 'project',
        text: 'Stale',
        existing: note,
      ),
      _failure(WorkFailure.stale),
    );
    await expectLater(
      work.saveNote(
        kind: WorkEntityKind.task,
        entityId: 'missing',
        text: 'Lost',
      ),
      _failure(WorkFailure.missing),
    );
  });

  test('old serialized records receive safe order and provenance defaults', () {
    final map = WorkTask(meta: _meta('old'), title: 'Old task').toMap()
      ..remove('order')
      ..remove('sourceTodoId');
    final restored = WorkTask.fromMap(map);
    expect(restored.order, 0);
    expect(restored.sourceTodoId, isNull);
  });

  test('planned work appears in Today without changing the task deadline', () async {
    final work = _controller();
    await work.saveTask(WorkTask(meta: _meta('planned'), title: 'Write notes'));
    await LocalStore.updateWork((data) => data.copyWith(blocks: [
      WorkPlanBlock(meta: _meta('block'), taskId: 'planned',
          startsAt: DateTime(2026, 9, 8, 23, 45), minutes: 45),
    ]));
    work.reload();
    final task = work.taskById('planned')!;
    expect(work.isForToday(task, DateTime(2026, 9, 9, 8)), isTrue);
    expect(work.isForToday(task, DateTime(2026, 9, 10)), isFalse);
    expect(task.dueDate, isNull);
    expect(task.startDate, isNull);
  });
}
