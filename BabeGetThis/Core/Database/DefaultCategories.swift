// Pre-populated categories, ported from Android `core/data/local/DefaultCategories.kt`.
// Fixed IDs so they're consistent across installs and platforms — important for sync.
// The taxonomy rules live in the Android repo's docs/technical-decisions/005-category-taxonomy.md.
enum DefaultCategories {
    static let all: [CategoryRecord] = [
        // Food
        .init(id: "cat-fruits-vegetables", name: "Fruits & Vegetables", isDefault: true),
        .init(id: "cat-dairy-eggs", name: "Dairy & Eggs", isDefault: true),
        .init(id: "cat-meat-seafood", name: "Meat & Seafood", isDefault: true),
        .init(id: "cat-bakery-bread", name: "Bakery & Bread", isDefault: true),
        .init(id: "cat-frozen-foods", name: "Frozen Foods", isDefault: true),
        .init(id: "cat-pantry-dry-goods", name: "Rice, Grains & Pasta", isDefault: true),
        .init(id: "cat-canned-jarred", name: "Canned & Jarred Goods", isDefault: true),
        .init(id: "cat-baking-supplies", name: "Baking & Dry Ingredients", isDefault: true),
        .init(id: "cat-spices-seasonings", name: "Spices & Seasonings", isDefault: true),
        .init(id: "cat-sauces-condiments", name: "Sauces, Condiments & Pastes", isDefault: true),
        .init(id: "cat-oils-vinegars", name: "Oils, Vinegars & Cooking Fats", isDefault: true),
        .init(id: "cat-breakfast-cereal", name: "Breakfast & Cereal", isDefault: true),
        .init(id: "cat-spreads", name: "Spreads, Honey & Jam", isDefault: true),
        .init(id: "cat-snacks", name: "Snacks", isDefault: true),
        .init(id: "cat-sweets-chocolate", name: "Sweets & Chocolate", isDefault: true),
        .init(id: "cat-ready-meals", name: "Ready Meals & Prepared Food", isDefault: true),
        .init(id: "cat-beverages", name: "Beverages", isDefault: true),
        .init(id: "cat-coffee-tea", name: "Coffee & Tea", isDefault: true),
        .init(id: "cat-alcohol", name: "Beer, Wine & Spirits", isDefault: true),

        // Home & household
        .init(id: "cat-household-cleaning", name: "Household & Cleaning", isDefault: true),
        .init(id: "cat-paper-disposables", name: "Paper & Disposables", isDefault: true),
        .init(id: "cat-kitchen-dining", name: "Kitchen & Dining", isDefault: true),
        .init(id: "cat-appliances", name: "Appliances", isDefault: true),
        .init(id: "cat-furniture-storage", name: "Furniture & Storage", isDefault: true),
        .init(id: "cat-home-decor", name: "Home Decor", isDefault: true),
        .init(id: "cat-bedding-bath", name: "Bedding & Bath", isDefault: true),
        .init(id: "cat-lighting-electrical", name: "Lighting & Electrical", isDefault: true),
        .init(id: "cat-hardware-diy", name: "Hardware & Tools", isDefault: true),
        .init(id: "cat-garden-outdoor", name: "Garden & Outdoor", isDefault: true),
        .init(id: "cat-automotive", name: "Automotive", isDefault: true),

        // Personal & health
        .init(id: "cat-toiletries-personal-care", name: "Personal Care & Beauty", isDefault: true),
        .init(id: "cat-health-pharmacy", name: "Health & Pharmacy", isDefault: true),

        // Wearables
        .init(id: "cat-clothing", name: "Clothing", isDefault: true),
        .init(id: "cat-underwear-sleepwear", name: "Underwear, Socks & Sleepwear", isDefault: true),
        .init(id: "cat-shoes", name: "Shoes & Footwear", isDefault: true),
        .init(id: "cat-accessories-jewelry", name: "Accessories & Jewelry", isDefault: true),
        .init(id: "cat-bags-luggage", name: "Bags & Luggage", isDefault: true),

        // People & pets
        .init(id: "cat-baby-kids", name: "Baby & Kids", isDefault: true),
        .init(id: "cat-pet-supplies", name: "Pet Supplies", isDefault: true),

        // Leisure & misc
        .init(id: "cat-electronics", name: "Electronics", isDefault: true),
        .init(id: "cat-toys-games", name: "Toys & Games", isDefault: true),
        .init(id: "cat-books-media", name: "Books & Media", isDefault: true),
        .init(id: "cat-sports-outdoors", name: "Sports & Outdoors", isDefault: true),
        .init(id: "cat-office-stationery", name: "Office & Stationery", isDefault: true),
        .init(id: "cat-arts-crafts", name: "Arts, Crafts & Hobbies", isDefault: true),
        .init(id: "cat-party-gifts", name: "Party, Gifts & Holiday", isDefault: true),
        .init(id: "cat-tobacco-vaping", name: "Tobacco & Vaping", isDefault: true),
        .init(id: "cat-other", name: "Other", isDefault: true),
    ]
}
