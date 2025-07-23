
-- =============================================
-- 1. Non-Clustered Index on Email (customers)
-- =============================================
CREATE NONCLUSTERED INDEX IX_Customers_Email
ON sales.customers (email);

-- =============================================
-- 2. Composite Index on category_id and brand_id (products)
-- =============================================
CREATE NONCLUSTERED INDEX IX_Products_Category_Brand
ON production.products (category_id, brand_id);

-- =============================================
-- 3. Index on order_date with included columns
-- =============================================
CREATE NONCLUSTERED INDEX IX_Orders_OrderDate
ON sales.orders (order_date)
INCLUDE (customer_id, store_id, order_status);

-- =============================================
-- Required Tables for Triggers
-- =============================================

-- Customer activity log
CREATE TABLE sales.customer_log (
    log_id INT IDENTITY(1,1) PRIMARY KEY,
    customer_id INT,
    action VARCHAR(50),
    log_date DATETIME DEFAULT GETDATE()
);

-- Price history tracking
CREATE TABLE production.price_history (
    history_id INT IDENTITY(1,1) PRIMARY KEY,
    product_id INT,
    old_price DECIMAL(10,2),
    new_price DECIMAL(10,2),
    change_date DATETIME DEFAULT GETDATE(),
    changed_by VARCHAR(100)
);

-- Order audit trail
CREATE TABLE sales.order_audit (
    audit_id INT IDENTITY(1,1) PRIMARY KEY,
    order_id INT,
    customer_id INT,
    store_id INT,
    staff_id INT,
    order_date DATE,
    audit_timestamp DATETIME DEFAULT GETDATE()
);

-- =============================================
-- 4. Trigger: Insert Welcome Log on New Customer
-- =============================================
CREATE TRIGGER trg_InsertCustomerLog
ON sales.customers
AFTER INSERT
AS
BEGIN
    INSERT INTO sales.customer_log (customer_id, action)
    SELECT customer_id, 'New customer added'
    FROM inserted;
END;

-- =============================================
-- 5. Trigger: Log Price Changes in Products
-- =============================================
CREATE TRIGGER trg_LogPriceChange
ON production.products
AFTER UPDATE
AS
BEGIN
    INSERT INTO production.price_history (product_id, old_price, new_price, changed_by)
    SELECT 
        i.product_id,
        d.list_price,
        i.list_price,
        SYSTEM_USER
    FROM inserted i
    JOIN deleted d ON i.product_id = d.product_id
    WHERE i.list_price <> d.list_price;
END;

-- =============================================
-- 6. INSTEAD OF DELETE Trigger on Categories
-- =============================================
CREATE TRIGGER trg_PreventCategoryDelete
ON production.categories
INSTEAD OF DELETE
AS
BEGIN
    IF EXISTS (
        SELECT 1 
        FROM deleted d
        JOIN production.products p ON d.category_id = p.category_id
    )
    BEGIN
        RAISERROR('Cannot delete category with associated products.', 16, 1);
    END
    ELSE
    BEGIN
        DELETE FROM production.categories
        WHERE category_id IN (SELECT category_id FROM deleted);
    END
END;

-- =============================================
-- 7. Trigger: Reduce Stock on Order Item Insert
-- =============================================
CREATE TRIGGER trg_ReduceStockOnOrderItemInsert
ON sales.order_items
AFTER INSERT
AS
BEGIN
    UPDATE s
    SET s.quantity = s.quantity - i.quantity
    FROM production.stocks s
    JOIN inserted i ON s.product_id = i.product_id;
END;

-- =============================================
-- 8. Trigger: Log New Orders in Audit Table
-- =============================================
CREATE TRIGGER trg_LogNewOrders
ON sales.orders
AFTER INSERT
AS
BEGIN
    INSERT INTO sales.order_audit (order_id, customer_id, store_id, staff_id, order_date)
    SELECT order_id, customer_id, store_id, staff_id, order_date
    FROM inserted;
END;
