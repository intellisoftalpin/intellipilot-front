// Underscore-prefixed fields read clearer than initializing formals in the
// public constructor — silence the lint at file scope.
// ignore_for_file: prefer_initializing_formals
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intellipilot/core/error/app_failure.dart';
import 'package:intellipilot/features/catalog/data/dtos/catalog_dtos.dart';
import 'package:intellipilot/features/catalog/domain/catalog_repository.dart';

sealed class CustomersState extends Equatable {
  const CustomersState();
  @override
  List<Object?> get props => const [];
}

final class CustomersLoading extends CustomersState {
  const CustomersLoading();
}

final class CustomersLoaded extends CustomersState {
  const CustomersLoaded({
    required this.customers,
    this.busy = false,
    this.lastError,
  });
  final List<Customer> customers;
  final bool busy;
  final AppFailure? lastError;

  CustomersLoaded copyWith({
    List<Customer>? customers,
    bool? busy,
    AppFailure? lastError,
  }) => CustomersLoaded(
    customers: customers ?? this.customers,
    busy: busy ?? this.busy,
    lastError: lastError,
  );

  @override
  List<Object?> get props => [
    customers.map((c) => c.id).toList(),
    busy,
    lastError,
  ];
}

final class CustomersLoadFailed extends CustomersState {
  const CustomersLoadFailed(this.failure);
  final AppFailure failure;
  @override
  List<Object?> get props => [failure];
}

class CustomersCubit extends Cubit<CustomersState> {
  CustomersCubit({required CatalogRepository repo, required this.projectId})
    : _repo = repo,
      super(const CustomersLoading());

  final CatalogRepository _repo;
  final String projectId;

  Future<void> load() async {
    emit(const CustomersLoading());
    final res = await _repo.listCustomers(projectId);
    res.when(
      ok: (c) => emit(CustomersLoaded(customers: c)),
      err: (f) => emit(CustomersLoadFailed(f)),
    );
  }

  Future<bool> create(CreateCustomerRequest body) async {
    final s = state;
    if (s is! CustomersLoaded) return false;
    emit(s.copyWith(busy: true, lastError: null));
    final res = await _repo.createCustomer(projectId, body);
    if (res.isErr) {
      emit(s.copyWith(busy: false, lastError: res.failureOrNull));
      return false;
    }
    await load();
    return true;
  }

  Future<bool> update(String customerId, UpdateCustomerRequest body) async {
    final s = state;
    if (s is! CustomersLoaded) return false;
    emit(s.copyWith(busy: true, lastError: null));
    final res = await _repo.updateCustomer(projectId, customerId, body);
    if (res.isErr) {
      emit(s.copyWith(busy: false, lastError: res.failureOrNull));
      return false;
    }
    await load();
    return true;
  }

  Future<void> delete(String customerId) async {
    final s = state;
    if (s is! CustomersLoaded) return;
    emit(s.copyWith(busy: true, lastError: null));
    final res = await _repo.deleteCustomer(projectId, customerId);
    if (res.isErr) {
      emit(s.copyWith(busy: false, lastError: res.failureOrNull));
      return;
    }
    await load();
  }
}
