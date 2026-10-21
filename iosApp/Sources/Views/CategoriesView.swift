import SwiftUI

/// Create, rename, reorder and delete the library's categories.
struct CategoriesView: View {
    @EnvironmentObject private var library: LibraryStore
    @State private var adding = false
    @State private var newName = ""
    @State private var renaming: LibraryCategory?
    @State private var renameText = ""

    private func memberCount(_ id: String) -> Int {
        library.entries.values.filter { $0.categories?.contains(id) == true }.count
    }

    var body: some View {
        List {
            if library.categories.isEmpty {
                Text("Crea categorías como Favoritos, Al día o Pendientes para organizar tu biblioteca.")
                    .foregroundStyle(.secondary)
            }
            ForEach(library.categories) { category in
                HStack {
                    Text(category.name)
                    Spacer()
                    Text("\(memberCount(category.id))")
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    renameText = category.name
                    renaming = category
                }
                .swipeActions {
                    Button("Eliminar", role: .destructive) {
                        library.deleteCategory(category.id)
                    }
                }
            }
            .onMove { offsets, destination in
                library.moveCategories(from: offsets, to: destination)
            }
        }
        .navigationTitle("Categorías")
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                EditButton()
                Button {
                    newName = ""
                    adding = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .alert("Nueva categoría", isPresented: $adding) {
            TextField("Nombre", text: $newName)
            Button("Cancelar", role: .cancel) {}
            Button("Crear") { library.addCategory(named: newName) }
        }
        .alert(
            "Renombrar categoría",
            isPresented: Binding(
                get: { renaming != nil },
                set: { if !$0 { renaming = nil } }
            ),
            presenting: renaming
        ) { category in
            TextField("Nombre", text: $renameText)
            Button("Cancelar", role: .cancel) {}
            Button("Guardar") { library.renameCategory(category.id, to: renameText) }
        }
    }
}
