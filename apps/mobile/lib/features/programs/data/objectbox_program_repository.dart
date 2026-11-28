import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ids/uuid_factory.dart';
import '../../../core/storage/objectbox_store_provider.dart';
import '../../../objectbox.g.dart';
import '../../catalog/domain/catalog_models.dart';
import '../../workouts/data/objectbox_workout_library_repository.dart';
import '../../workouts/data/workout_entities.dart';
import '../../workouts/domain/workout_library_models.dart';
import '../domain/program_models.dart';
import '../domain/program_repository.dart';
import '../domain/program_schedule.dart';

final programRepositoryProvider = Provider<ProgramRepository>((ref) {
  return ObjectBoxProgramRepository(ref.watch(objectBoxStoreProvider));
});

class ObjectBoxProgramRepository implements ProgramRepository {
  ObjectBoxProgramRepository(this._store, {UuidFactory? uuidFactory})
    : _ids = uuidFactory ?? SecureUuidFactory(),
      _library = ObjectBoxWorkoutLibraryRepository(
        _store,
        uuidFactory: uuidFactory,
      ),
      _programs = _store.box<TrainingProgramEntity>(),
      _days = _store.box<ProgramDayEntity>(),
      _plans = _store.box<WorkoutPlanEntity>(),
      _items = _store.box<PlanExerciseEntity>();

  final Store _store;
  final UuidFactory _ids;
  final ObjectBoxWorkoutLibraryRepository _library;
  final Box<TrainingProgramEntity> _programs;
  final Box<ProgramDayEntity> _days;
  final Box<WorkoutPlanEntity> _plans;
  final Box<PlanExerciseEntity> _items;

  /// Called after each import step: `exercises`, `plans`, `rows`, `program`,
  /// `days`. A throw rolls the whole import back.
  @visibleForTesting
  void Function(String step)? debugImportHook;

  TrainingProgramEntity? _byUuid(String uuid) {
    final query = _programs
        .query(TrainingProgramEntity_.uuid.equals(uuid))
        .build();
    try {
      return query.findFirst();
    } finally {
      query.close();
    }
  }

  List<ProgramDayEntity> _daysOf(String programUuid) {
    final query = _days
        .query(ProgramDayEntity_.programUuid.equals(programUuid))
        .build();
    try {
      return query.find()..sort((a, b) => a.dayIndex.compareTo(b.dayIndex));
    } finally {
      query.close();
    }
  }

  List<WorkoutPlanEntity> _plansOf(String programUuid) {
    final query = _plans
        .query(WorkoutPlanEntity_.programUuid.equals(programUuid))
        .build();
    try {
      return query.find();
    } finally {
      query.close();
    }
  }

  TrainingProgramRecord _record(TrainingProgramEntity p) =>
      TrainingProgramRecord(
        uuid: p.uuid,
        name: p.name,
        description: p.description,
        sourceId: p.sourceId,
        sourceRelease: p.sourceRelease,
        firstDayWeekday: p.firstDayWeekday,
        isActive: p.isActive,
        activatedLocalDate: p.activatedLocalDate,
        updatedAtMs: p.updatedAtMs,
        archivedAtMs: p.archivedAtMs,
        days: List.unmodifiable([
          for (final d in _daysOf(p.uuid))
            ProgramDayRecord(
              uuid: d.uuid,
              dayIndex: d.dayIndex,
              planUuid: d.planUuid,
            ),
        ]),
      );

  int _now() => DateTime.now().toUtc().millisecondsSinceEpoch;

  TrainingProgramEntity _live(String programUuid) {
    final program = _byUuid(programUuid);
    if (program == null || program.archivedAtMs != null) {
      throw StateError('Unknown or archived program');
    }
    return program;
  }

  @override
  TrainingProgramRecord importProgram({
    required String requestUuid,
    required CatalogProgram program,
    required Map<String, List<TemplateRowInput>> templateRows,
    required Map<String, String> templateNames,
    Map<String, String> templateDescriptions = const {},
    required int release,
    required int firstDayWeekday,
    required bool makeActive,
    required DateTime localToday,
  }) {
    final label = program.name.trim();
    if (requestUuid.isEmpty ||
        label.isEmpty ||
        label.length > 100 ||
        program.week.length != 7 ||
        firstDayWeekday < 1 ||
        firstDayWeekday > 7) {
      throw ArgumentError('Invalid program import');
    }
    final templateIds = <String>{for (final id in program.week) ?id}.toList();
    final items = <String, List<PlanExerciseRecord>>{};
    for (final id in templateIds) {
      final rows = templateRows[id];
      final name = templateNames[id]?.trim();
      if (rows == null ||
          rows.isEmpty ||
          rows.length > 100 ||
          name == null ||
          name.isEmpty ||
          name.length > 100) {
        throw ArgumentError('Program template is missing');
      }
      items[id] = _library.planItemsFromRows(rows);
    }
    return _store.runInTransaction(TxMode.write, () {
      final existing = _byUuid(requestUuid);
      if (existing != null) return _record(existing);
      for (final id in templateIds) {
        for (final row in templateRows[id]!) {
          _library.materializeInTransaction(row.exercise, release);
        }
      }
      debugImportHook?.call('exercises');
      final now = _now();
      final planUuids = {for (final id in templateIds) id: _ids.newId()};
      for (final id in templateIds) {
        _plans.put(
          WorkoutPlanEntity(
            uuid: planUuids[id]!,
            name: templateNames[id]!.trim(),
            description: _clip(templateDescriptions[id] ?? ''),
            createdAtMs: now,
            updatedAtMs: now,
            programUuid: requestUuid,
          ),
        );
      }
      debugImportHook?.call('plans');
      for (final id in templateIds) {
        for (final item in items[id]!) {
          _items.put(
            PlanExerciseEntity(
              uuid: item.uuid,
              planUuid: planUuids[id]!,
              exerciseUuid: item.exerciseUuid,
              position: item.position,
              targetSets: item.targetSets,
              targetRepsMin: item.targetRepsMin,
              targetRepsMax: item.targetRepsMax,
              targetDurationSeconds: item.targetDurationSeconds,
              restSeconds: item.restSeconds,
              notes: item.notes.trim(),
            ),
          );
        }
      }
      debugImportHook?.call('rows');
      final unique = _uniqueName(label);
      if (makeActive) _deactivateAll(now);
      final entity = TrainingProgramEntity(
        uuid: requestUuid,
        name: unique,
        description: program.description,
        sourceId: program.id,
        sourceRelease: release,
        firstDayWeekday: firstDayWeekday,
        isActive: makeActive,
        activatedLocalDate: makeActive ? localDateKey(localToday) : null,
        createdAtMs: now,
        updatedAtMs: now,
      );
      _programs.put(entity);
      debugImportHook?.call('program');
      for (var i = 0; i < 7; i++) {
        final id = program.week[i];
        _days.put(
          ProgramDayEntity(
            uuid: _ids.newId(),
            programUuid: requestUuid,
            dayIndex: i,
            planUuid: id == null ? null : planUuids[id],
          ),
        );
      }
      debugImportHook?.call('days');
      return _record(entity);
    });
  }

  /// [label] made unique among live program names by adding " (n)".
  String _uniqueName(String label) {
    final taken = {
      for (final p in _programs.getAll())
        if (p.archivedAtMs == null) p.name.trim().toLowerCase(),
    };
    var unique = label;
    for (var n = 2; taken.contains(unique.toLowerCase()); n++) {
      final suffix = ' ($n)';
      final room = 100 - suffix.length;
      unique =
          '${label.length > room ? label.substring(0, room).trimRight() : label}$suffix';
    }
    return unique;
  }

  /// A source's name and description, checked before any write.
  ({String name, String description}) _sourceText(ProgramWorkoutSource s) {
    final (name, description) = switch (s) {
      DraftWorkoutSource() => (s.name, s.description),
      TemplateWorkoutSource() => (s.name, s.description),
      CopyWorkoutSource() => ('', ''),
    };
    return (name: name.trim(), description: _clip(description));
  }

  /// Rows of [s] ready to write under a new plan. Runs inside the write
  /// transaction: template exercises are materialized, copies read the live
  /// source plan. Returns the plan name and description too.
  ({String name, String description, List<PlanExerciseRecord> items}) _resolve(
    ProgramWorkoutSource s,
  ) {
    switch (s) {
      case DraftWorkoutSource():
        final text = _sourceText(s);
        if (text.name.isEmpty ||
            text.name.length > 100 ||
            s.rows.length > 100) {
          throw ArgumentError('Invalid workout name or size');
        }
        final items = <PlanExerciseRecord>[];
        for (var i = 0; i < s.rows.length; i++) {
          final r = s.rows[i];
          r.validate();
          final definition = _store
              .box<ExerciseDefinitionEntity>()
              .query(ExerciseDefinitionEntity_.uuid.equals(r.exerciseUuid))
              .build();
          final ExerciseDefinitionEntity? found;
          try {
            found = definition.findFirst();
          } finally {
            definition.close();
          }
          if (found == null) {
            throw StateError('Workout refers to an unknown exercise');
          }
          final timed = found.inputMode == 'duration';
          if (timed && (r.targetRepsMin != null || r.targetRepsMax != null)) {
            throw ArgumentError('Timed exercise targets seconds, not reps');
          }
          if (!timed && r.targetDurationSeconds != null) {
            throw ArgumentError('Rep exercise targets reps, not seconds');
          }
          items.add(
            PlanExerciseRecord(
              uuid: _ids.newId(),
              exerciseUuid: r.exerciseUuid,
              position: i,
              targetSets: r.targetSets,
              targetRepsMin: r.targetRepsMin,
              targetRepsMax: r.targetRepsMax,
              targetDurationSeconds: r.targetDurationSeconds,
              restSeconds: r.restSeconds,
              notes: r.notes.trim(),
            ),
          );
        }
        return (name: text.name, description: text.description, items: items);
      case TemplateWorkoutSource():
        final text = _sourceText(s);
        if (text.name.isEmpty ||
            text.name.length > 100 ||
            s.rows.isEmpty ||
            s.rows.length > 100) {
          throw ArgumentError('Invalid template workout');
        }
        final items = _library.planItemsFromRows(s.rows);
        for (final row in s.rows) {
          _library.materializeInTransaction(row.exercise, s.release);
        }
        return (name: text.name, description: text.description, items: items);
      case CopyWorkoutSource():
        final source = _library.getPlan(s.planUuid);
        if (source == null) throw ArgumentError('Workout to copy is missing');
        return (
          name: source.name,
          description: source.description,
          items: [
            for (final row in source.exercises)
              PlanExerciseRecord(
                uuid: _ids.newId(),
                exerciseUuid: row.exerciseUuid,
                position: row.position,
                targetSets: row.targetSets,
                targetRepsMin: row.targetRepsMin,
                targetRepsMax: row.targetRepsMax,
                targetDurationSeconds: row.targetDurationSeconds,
                restSeconds: row.restSeconds,
                notes: row.notes,
              ),
          ],
        );
    }
  }

  void _putPlan(
    String uuid,
    String programUuid,
    String name,
    String text,
    int now,
  ) {
    _plans.put(
      WorkoutPlanEntity(
        uuid: uuid,
        name: name,
        description: text,
        createdAtMs: now,
        updatedAtMs: now,
        programUuid: programUuid,
      ),
    );
  }

  void _putItems(String planUuid, List<PlanExerciseRecord> items) {
    for (final item in items) {
      _items.put(
        PlanExerciseEntity(
          uuid: item.uuid,
          planUuid: planUuid,
          exerciseUuid: item.exerciseUuid,
          position: item.position,
          targetSets: item.targetSets,
          targetRepsMin: item.targetRepsMin,
          targetRepsMax: item.targetRepsMax,
          targetDurationSeconds: item.targetDurationSeconds,
          restSeconds: item.restSeconds,
          notes: item.notes.trim(),
        ),
      );
    }
  }

  @override
  TrainingProgramRecord createProgram({
    required String requestUuid,
    required String name,
    required String description,
    required List<ProgramWorkoutSource> workouts,
    required List<int?> week,
    required int firstDayWeekday,
    required bool makeActive,
    required DateTime localToday,
  }) {
    final label = name.trim();
    if (requestUuid.isEmpty ||
        label.isEmpty ||
        label.length > 100 ||
        week.length != 7 ||
        firstDayWeekday < 1 ||
        firstDayWeekday > 7) {
      throw ArgumentError('Invalid program');
    }
    if (workouts.length > maxProgramWorkouts) {
      throw const ProgramWorkoutLimit();
    }
    final used = <int>{};
    for (final index in week) {
      if (index == null) continue;
      if (index < 0 || index >= workouts.length) {
        throw ArgumentError('Day names an unknown workout');
      }
      used.add(index);
    }
    if (used.isEmpty || used.length != workouts.length) {
      throw ArgumentError(
        'A program needs a training day and no unused workout',
      );
    }
    return _store.runInTransaction(TxMode.write, () {
      final existing = _byUuid(requestUuid);
      if (existing != null) return _record(existing);
      final resolved = [for (final w in workouts) _resolve(w)];
      debugImportHook?.call('exercises');
      final now = _now();
      final planUuids = [for (final _ in resolved) _ids.newId()];
      for (var i = 0; i < resolved.length; i++) {
        _putPlan(
          planUuids[i],
          requestUuid,
          resolved[i].name,
          resolved[i].description,
          now,
        );
      }
      debugImportHook?.call('plans');
      for (var i = 0; i < resolved.length; i++) {
        _putItems(planUuids[i], resolved[i].items);
      }
      debugImportHook?.call('rows');
      final unique = _uniqueName(label);
      if (makeActive) _deactivateAll(now);
      final entity = TrainingProgramEntity(
        uuid: requestUuid,
        name: unique,
        description: _clip(description),
        sourceId: 'custom',
        sourceRelease: 0,
        firstDayWeekday: firstDayWeekday,
        isActive: makeActive,
        activatedLocalDate: makeActive ? localDateKey(localToday) : null,
        createdAtMs: now,
        updatedAtMs: now,
      );
      _programs.put(entity);
      debugImportHook?.call('program');
      for (var i = 0; i < 7; i++) {
        final index = week[i];
        _days.put(
          ProgramDayEntity(
            uuid: _ids.newId(),
            programUuid: requestUuid,
            dayIndex: i,
            planUuid: index == null ? null : planUuids[index],
          ),
        );
      }
      debugImportHook?.call('days');
      return _record(entity);
    });
  }

  @override
  void updateDetails(
    String programUuid, {
    required String name,
    required String description,
  }) {
    final label = name.trim();
    if (label.isEmpty || label.length > 100) {
      throw ArgumentError('Invalid program name');
    }
    _store.runInTransaction(TxMode.write, () {
      final program = _live(programUuid);
      program.name = label;
      program.description = _clip(description);
      program.updatedAtMs = _now();
      _programs.put(program);
    });
  }

  @override
  String addWorkout(
    String programUuid,
    ProgramWorkoutSource source, {
    required int dayIndex,
    required String requestUuid,
  }) {
    if (dayIndex < 0 || dayIndex > 6) throw ArgumentError('Invalid day');
    return _store.runInTransaction(TxMode.write, () {
      final program = _live(programUuid);
      // A repeated request returns the workout it already made.
      if (_plansOf(programUuid).any((p) => p.uuid == requestUuid)) {
        return requestUuid;
      }
      final live = _plansOf(programUuid).where((p) => p.archivedAtMs == null);
      if (live.length >= maxProgramWorkouts) {
        throw const ProgramWorkoutLimit();
      }
      final resolved = _resolve(source);
      final now = _now();
      _putPlan(
        requestUuid,
        programUuid,
        resolved.name,
        resolved.description,
        now,
      );
      _putItems(requestUuid, resolved.items);
      _assignDay(programUuid, dayIndex, requestUuid, now);
      program.updatedAtMs = now;
      _programs.put(program);
      return requestUuid;
    });
  }

  /// Points a day at [planUuid] and archives the workout it used before when
  /// no other day uses it. Runs inside a write transaction.
  void _assignDay(String programUuid, int dayIndex, String? planUuid, int now) {
    final days = _daysOf(programUuid);
    final day = days.firstWhere((d) => d.dayIndex == dayIndex);
    final old = day.planUuid;
    day.planUuid = planUuid;
    _days.put(day);
    if (old == null || old == planUuid) return;
    if (days.any((d) => d.dayIndex != dayIndex && d.planUuid == old)) return;
    for (final plan in _plansOf(programUuid)) {
      if (plan.uuid == old && plan.archivedAtMs == null) {
        plan.archivedAtMs = now;
        plan.updatedAtMs = now;
        _plans.put(plan);
      }
    }
  }

  /// At most 1000 characters, never splitting a surrogate pair.
  String _clip(String text) {
    var cut = text.length > 1000 ? 1000 : text.length;
    if (cut < text.length &&
        cut > 0 &&
        (text.codeUnitAt(cut - 1) & 0xFC00) == 0xD800) {
      cut--;
    }
    return text.substring(0, cut).trim();
  }

  void _deactivateAll(int now, {String? except}) {
    for (final other in _programs.getAll()) {
      if (other.isActive && other.uuid != except) {
        other.isActive = false;
        other.updatedAtMs = now;
        _programs.put(other);
      }
    }
  }

  @override
  void setActive(String programUuid, bool active, DateTime localToday) {
    _store.runInTransaction(TxMode.write, () {
      final program = _live(programUuid);
      final now = _now();
      if (active) {
        _deactivateAll(now, except: programUuid);
        program.activatedLocalDate = localDateKey(localToday);
      }
      program.isActive = active;
      program.updatedAtMs = now;
      _programs.put(program);
    });
  }

  @override
  void setFirstWeekday(String programUuid, int weekday) {
    if (weekday < 1 || weekday > 7) throw ArgumentError('Invalid weekday');
    _store.runInTransaction(TxMode.write, () {
      final program = _live(programUuid);
      program.firstDayWeekday = weekday;
      program.updatedAtMs = _now();
      _programs.put(program);
    });
  }

  @override
  void setDayPlan(String programUuid, int dayIndex, String? planUuid) {
    if (dayIndex < 0 || dayIndex > 6) throw ArgumentError('Invalid day');
    _store.runInTransaction(TxMode.write, () {
      final program = _live(programUuid);
      if (planUuid != null &&
          !_plansOf(
            programUuid,
          ).any((plan) => plan.uuid == planUuid && plan.archivedAtMs == null)) {
        throw ArgumentError('Plan does not belong to this program');
      }
      final now = _now();
      _assignDay(programUuid, dayIndex, planUuid, now);
      program.updatedAtMs = now;
      _programs.put(program);
    });
  }

  @override
  List<WorkoutPlanRecord> programPlans(String programUuid) {
    return _store.runInTransaction(TxMode.read, () {
      final plans = _plansOf(programUuid)
        ..removeWhere((p) => p.archivedAtMs != null)
        ..sort((a, b) => a.id.compareTo(b.id));
      return [for (final plan in plans) ?_library.getPlan(plan.uuid)];
    });
  }

  @override
  void archiveProgram(String programUuid, int nowMs) {
    _store.runInTransaction(TxMode.write, () {
      final program = _byUuid(programUuid);
      if (program == null) throw StateError('Unknown program');
      if (program.archivedAtMs != null) return;
      for (final plan in _plansOf(programUuid)) {
        plan.archivedAtMs ??= nowMs;
        _plans.put(plan);
      }
      program
        ..archivedAtMs = nowMs
        ..isActive = false
        ..updatedAtMs = nowMs;
      _programs.put(program);
    });
  }

  @override
  TrainingProgramRecord? getProgram(String programUuid) {
    return _store.runInTransaction(TxMode.read, () {
      final program = _byUuid(programUuid);
      return program == null ? null : _record(program);
    });
  }

  @override
  List<TrainingProgramRecord> listPrograms() {
    return _store.runInTransaction(TxMode.read, () {
      final list = _programs.getAll()
        ..removeWhere((p) => p.archivedAtMs != null)
        ..sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs));
      return list.map(_record).toList(growable: false);
    });
  }

  @override
  Stream<List<TrainingProgramRecord>> watchPrograms() {
    return _programs
        .query()
        .watch(triggerImmediately: true)
        .map((_) => listPrograms());
  }

  @override
  TrainingProgramRecord? activeProgram() {
    return _store.runInTransaction(TxMode.read, () {
      for (final p in _programs.getAll()) {
        if (p.isActive && p.archivedAtMs == null) return _record(p);
      }
      return null;
    });
  }
}
