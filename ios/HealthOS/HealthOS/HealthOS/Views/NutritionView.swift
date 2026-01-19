//
//  NutritionView.swift
//  HealthOS
//
//  Created by Codex on 1/20/26.
//

import PhotosUI
import SwiftUI

struct NutritionView: View {
    @State private var meals: [MealEntry] = MealEntry.sampleMeals
    @State private var showAddMeal: Bool = false
    @State private var selectedDate: Date = Date()

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    goalsCard
                    mealList
                }
                .padding()
            }
            .navigationTitle("Nutrition")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddMeal = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $showAddMeal) {
            AddMealSheet { entry in
                meals.insert(entry, at: 0)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Meals & Macros")
                .font(.title2)
                .bold()
            Text("Track meals by photo or natural language, and roll them into your daily targets.")
                .foregroundStyle(.secondary)
                .font(.subheadline)
        }
    }

    private var goalsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Daily Goals")
                .font(.headline)

            HStack(spacing: 12) {
                goalPill(title: "Calories", value: "1,850 / 2,400")
                goalPill(title: "Protein", value: "120g / 160g")
                goalPill(title: "Carbs", value: "140g / 220g")
            }

            Text("Tap a meal to edit macros or add notes.")
                .foregroundStyle(.secondary)
                .font(.footnote)
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func goalPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
                .bold()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(Color.secondary.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var mealList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Meals")
                    .font(.title3)
                    .bold()
                Spacer()
                DatePicker(
                    "",
                    selection: $selectedDate,
                    displayedComponents: [.date]
                )
                .labelsHidden()
            }

            if meals.isEmpty {
                Text("No meals logged yet.")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                VStack(spacing: 12) {
                    ForEach(meals) { meal in
                        MealRow(meal: meal)
                    }
                }
            }
        }
    }
}

private struct MealRow: View {
    let meal: MealEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(meal.title)
                        .font(.headline)
                    Text(meal.date.formatted(date: .abbreviated, time: .shortened))
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                Spacer()
                Text("\(meal.calories) kcal")
                    .font(.headline)
            }

            HStack(spacing: 12) {
                macroPill(title: "P", value: "\(meal.protein)g")
                macroPill(title: "C", value: "\(meal.carbs)g")
                macroPill(title: "F", value: "\(meal.fat)g")
            }

            if !meal.notes.isEmpty {
                Text(meal.notes)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func macroPill(title: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
                .bold()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(Color.secondary.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct AddMealSheet: View {
    @State private var usePhoto: Bool = true
    @State private var notes: String = ""
    @State private var title: String = ""
    @State private var calories: String = ""
    @State private var protein: String = ""
    @State private var carbs: String = ""
    @State private var fat: String = ""
    @State private var selectedItem: PhotosPickerItem? = nil
    @Environment(\.dismiss) private var dismiss

    let onSave: (MealEntry) -> Void

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("Entry mode", selection: $usePhoto) {
                        Text("Photo").tag(true)
                        Text("Natural language").tag(false)
                    }
                    .pickerStyle(.segmented)

                    if usePhoto {
                        PhotosPicker(selection: $selectedItem, matching: .images) {
                            VStack(spacing: 8) {
                                Image(systemName: "camera.viewfinder")
                                    .font(.largeTitle)
                                Text(selectedItem == nil ? "Add a meal photo" : "Photo selected")
                                    .font(.headline)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                    } else {
                        TextEditor(text: $notes)
                            .frame(minHeight: 120)
                            .padding(8)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(alignment: .topLeading) {
                                if notes.isEmpty {
                                    Text("Example: Chicken bowl with rice, avocado, salsa…")
                                        .foregroundStyle(.secondary)
                                        .padding(.top, 16)
                                        .padding(.leading, 12)
                                }
                            }
                    }

                    VStack(spacing: 12) {
                        TextField("Meal title", text: $title)
                            .textFieldStyle(.roundedBorder)
                        TextField("Calories", text: $calories)
                            .keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder)
                        HStack {
                            TextField("Protein (g)", text: $protein)
                                .keyboardType(.numberPad)
                                .textFieldStyle(.roundedBorder)
                            TextField("Carbs (g)", text: $carbs)
                                .keyboardType(.numberPad)
                                .textFieldStyle(.roundedBorder)
                            TextField("Fat (g)", text: $fat)
                                .keyboardType(.numberPad)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Add meal")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let entry = MealEntry(
                            title: title.isEmpty ? "Untitled meal" : title,
                            date: Date(),
                            calories: Int(calories) ?? 0,
                            protein: Int(protein) ?? 0,
                            carbs: Int(carbs) ?? 0,
                            fat: Int(fat) ?? 0,
                            notes: notes
                        )
                        onSave(entry)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct MealEntry: Identifiable {
    let id = UUID()
    let title: String
    let date: Date
    let calories: Int
    let protein: Int
    let carbs: Int
    let fat: Int
    let notes: String

    static let sampleMeals: [MealEntry] = [
        MealEntry(title: "Oatmeal + berries", date: Date().addingTimeInterval(-3600 * 3), calories: 420, protein: 18, carbs: 62, fat: 10, notes: "Added almond butter."),
        MealEntry(title: "Chicken bowl", date: Date().addingTimeInterval(-3600 * 8), calories: 610, protein: 48, carbs: 54, fat: 18, notes: "Felt great post workout.")
    ]
}
